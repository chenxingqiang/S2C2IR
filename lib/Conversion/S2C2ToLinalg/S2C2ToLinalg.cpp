//===- S2C2ToLinalg.cpp - Convert compute dialect to linalg -----*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/Compute/ComputeOps.h"
#include "s2c2/S2C2Passes.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/Math/IR/Math.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "llvm/Support/ErrorHandling.h"

namespace mlir::s2c2 {
#define GEN_PASS_DEF_CONVERTCOMPTOLINALG
#include "s2c2/S2C2Passes.h.inc"

using comp::Activation;
using comp::ElemwiseKind;
using comp::ElemwiseOp;
using comp::GatedMLPOp;
using comp::MatmulOp;

namespace {
static FailureOr<RankedTensorType> inferMatmulType(Type lhsType, Type rhsType) {
  auto lhs = dyn_cast<RankedTensorType>(lhsType);
  auto rhs = dyn_cast<RankedTensorType>(rhsType);
  if (!lhs || !rhs || lhs.getRank() != 2 || rhs.getRank() != 2)
    return failure();
  if (lhs.getElementType() != rhs.getElementType())
    return failure();
  if (!lhs.isDynamicDim(1) && !rhs.isDynamicDim(0) &&
      lhs.getDimSize(1) != rhs.getDimSize(0))
    return failure();
  return RankedTensorType::get({lhs.getDimSize(0), rhs.getDimSize(1)},
                               lhs.getElementType());
}

static Value floatConst(OpBuilder &b, Location loc, Type ty, double value) {
  return b.create<arith::ConstantOp>(loc, b.getFloatAttr(ty, value));
}

static Value emptyTensor(OpBuilder &b, Location loc, RankedTensorType ty) {
  return b.create<tensor::EmptyOp>(loc, ty.getShape(), ty.getElementType());
}

static Value zeroFilled(OpBuilder &b, Location loc, RankedTensorType ty) {
  Value empty = emptyTensor(b, loc, ty);
  Value zero = floatConst(b, loc, ty.getElementType(), 0.0);
  auto fill = b.create<linalg::FillOp>(loc, ValueRange{zero}, ValueRange{empty});
  return fill.getResultTensors().front();
}

static Value emitMatmul(OpBuilder &b, Location loc, Value lhs, Value rhs,
                        RankedTensorType resultTy) {
  Value init = zeroFilled(b, loc, resultTy);
  auto op = b.create<linalg::MatmulOp>(loc, TypeRange{resultTy},
                                       ValueRange{lhs, rhs}, ValueRange{init});
  return op.getResultTensors().front();
}

static Value emitSilu(OpBuilder &b, Location loc, Value x) {
  Type ty = x.getType();
  Value neg = b.create<arith::NegFOp>(loc, x);
  Value ex = b.create<math::ExpOp>(loc, neg);
  Value one = floatConst(b, loc, ty, 1.0);
  Value den = b.create<arith::AddFOp>(loc, one, ex);
  Value sig = b.create<arith::DivFOp>(loc, one, den);
  return b.create<arith::MulFOp>(loc, x, sig);
}

static Value emitGelu(OpBuilder &b, Location loc, Value x) {
  Type ty = x.getType();
  Value sqrt2 = floatConst(b, loc, ty, 1.4142135623730951);
  Value half = floatConst(b, loc, ty, 0.5);
  Value one = floatConst(b, loc, ty, 1.0);
  Value scaled = b.create<arith::DivFOp>(loc, x, sqrt2);
  Value erf = b.create<math::ErfOp>(loc, scaled);
  Value inner = b.create<arith::AddFOp>(loc, one, erf);
  Value halfX = b.create<arith::MulFOp>(loc, half, x);
  return b.create<arith::MulFOp>(loc, halfX, inner);
}

static Value emitRelu(OpBuilder &b, Location loc, Value x) {
  Value zero = floatConst(b, loc, x.getType(), 0.0);
  return b.create<arith::MaximumFOp>(loc, x, zero);
}

static Value emitUnaryMap(OpBuilder &b, Location loc, Value input,
                          RankedTensorType resultTy,
                          function_ref<Value(OpBuilder &, Location, Value)> fn) {
  Value init = emptyTensor(b, loc, resultTy);
  auto map = b.create<linalg::MapOp>(
      loc, ValueRange{input}, init,
      [&](OpBuilder &body, Location bodyLoc, ValueRange args) {
        Value y = fn(body, bodyLoc, args[0]);
        body.create<linalg::YieldOp>(bodyLoc, y);
      });
  return map.getResult().front();
}

struct ConvertMatmul : OpRewritePattern<MatmulOp> {
  using OpRewritePattern<MatmulOp>::OpRewritePattern;

  LogicalResult matchAndRewrite(MatmulOp op,
                                PatternRewriter &rewriter) const override {
    auto resultTy = dyn_cast<RankedTensorType>(op.getType());
    auto inferred = inferMatmulType(op.getLhs().getType(), op.getRhs().getType());
    if (!resultTy || failed(inferred) || *inferred != resultTy)
      return rewriter.notifyMatchFailure(op, "expected rank-2 matmul types");
    rewriter.replaceOp(
        op, emitMatmul(rewriter, op.getLoc(), op.getLhs(), op.getRhs(), resultTy));
    return success();
  }
};

struct ConvertElemwise : OpRewritePattern<ElemwiseOp> {
  using OpRewritePattern<ElemwiseOp>::OpRewritePattern;

  LogicalResult matchAndRewrite(ElemwiseOp op,
                                PatternRewriter &rewriter) const override {
    auto resultTy = dyn_cast<RankedTensorType>(op.getType());
    if (!resultTy)
      return rewriter.notifyMatchFailure(op, "expected ranked tensor result");
    Location loc = op.getLoc();
    ValueRange ins = op.getInputs();
    Value empty = emptyTensor(rewriter, loc, resultTy);

    switch (op.getKind()) {
    case ElemwiseKind::ADD: {
      if (ins.size() != 2)
        return rewriter.notifyMatchFailure(op, "add expects two inputs");
      auto add = rewriter.create<linalg::AddOp>(loc, ins, ValueRange{empty});
      rewriter.replaceOp(op, add.getResultTensors().front());
      return success();
    }
    case ElemwiseKind::MUL: {
      if (ins.size() != 2)
        return rewriter.notifyMatchFailure(op, "mul expects two inputs");
      auto mul = rewriter.create<linalg::MulOp>(loc, ins, ValueRange{empty});
      rewriter.replaceOp(op, mul.getResultTensors().front());
      return success();
    }
    case ElemwiseKind::SILU:
    case ElemwiseKind::GELU:
    case ElemwiseKind::RELU: {
      if (ins.size() != 1)
        return rewriter.notifyMatchFailure(op, "unary elemwise expects one input");
      auto fn = op.getKind() == ElemwiseKind::SILU   ? emitSilu
                : op.getKind() == ElemwiseKind::GELU ? emitGelu
                                                     : emitRelu;
      rewriter.replaceOp(op, emitUnaryMap(rewriter, loc, ins[0], resultTy, fn));
      return success();
    }
    }
    llvm_unreachable("unknown elemwise kind");
  }
};

struct ConvertGatedMLP : OpRewritePattern<GatedMLPOp> {
  using OpRewritePattern<GatedMLPOp>::OpRewritePattern;

  LogicalResult matchAndRewrite(GatedMLPOp op,
                                PatternRewriter &rewriter) const override {
    auto gateTy = inferMatmulType(op.getInput().getType(),
                                  op.getGateWeight().getType());
    auto upTy = inferMatmulType(op.getInput().getType(),
                                op.getUpWeight().getType());
    if (failed(gateTy) || failed(upTy) || *gateTy != *upTy)
      return rewriter.notifyMatchFailure(
          op, "gated_mlp requires rank-2 matmul-shaped operands");
    auto downTy = inferMatmulType(*gateTy, op.getDownWeight().getType());
    if (failed(downTy) || *downTy != op.getOutput().getType())
      return rewriter.notifyMatchFailure(
          op, "gated_mlp down-projection type mismatch");

    Location loc = op.getLoc();
    Value gate =
        emitMatmul(rewriter, loc, op.getInput(), op.getGateWeight(), *gateTy);
    Value up =
        emitMatmul(rewriter, loc, op.getInput(), op.getUpWeight(), *upTy);

    Activation act = op.getActivation().value_or(Activation::SILU);
    auto fn = act == Activation::SILU   ? emitSilu
              : act == Activation::GELU ? emitGelu
                                        : emitRelu;
    Value actv = emitUnaryMap(rewriter, loc, gate, *gateTy, fn);

    Value empty = emptyTensor(rewriter, loc, *gateTy);
    auto hidden =
        rewriter.create<linalg::MulOp>(loc, ValueRange{actv, up}, ValueRange{empty});
    Value out = emitMatmul(rewriter, loc, hidden.getResultTensors().front(),
                           op.getDownWeight(), *downTy);
    rewriter.replaceOp(op, out);
    return success();
  }
};

struct ConvertCompToLinalg
    : impl::ConvertCompToLinalgBase<ConvertCompToLinalg> {
  using impl::ConvertCompToLinalgBase<
      ConvertCompToLinalg>::ConvertCompToLinalgBase;

  void runOnOperation() override {
    RewritePatternSet patterns(&getContext());
    patterns.add<ConvertGatedMLP, ConvertMatmul, ConvertElemwise>(&getContext());
    if (failed(applyPatternsGreedily(getOperation(), std::move(patterns))))
      signalPassFailure();
  }
};
} // namespace
} // namespace mlir::s2c2
