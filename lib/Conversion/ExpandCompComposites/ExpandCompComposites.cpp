//===- ExpandCompComposites.cpp - Expand fused compute ops ------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/Compute/ComputeOps.h"
#include "s2c2/S2C2Passes.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "llvm/Support/ErrorHandling.h"

namespace mlir::s2c2 {
#define GEN_PASS_DEF_EXPANDCOMPCOMPOSITES
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

static ElemwiseKind activationKind(Activation act) {
  switch (act) {
  case Activation::SILU:
    return ElemwiseKind::SILU;
  case Activation::GELU:
    return ElemwiseKind::GELU;
  case Activation::RELU:
    return ElemwiseKind::RELU;
  }
  llvm_unreachable("unknown gated-mlp activation");
}

struct ExpandGatedMLP : OpRewritePattern<GatedMLPOp> {
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
    comp::UnitAttr unit = op.getUnitAttr();
    Value gate =
        rewriter.create<MatmulOp>(loc, *gateTy, op.getInput(),
                                  op.getGateWeight(), unit);
    Value up = rewriter.create<MatmulOp>(loc, *upTy, op.getInput(),
                                         op.getUpWeight(), unit);

    Activation act = op.getActivation().value_or(Activation::SILU);
    Value actv = rewriter.create<ElemwiseOp>(
        loc, *gateTy, ValueRange{gate}, activationKind(act), unit);
    Value hidden = rewriter.create<ElemwiseOp>(
        loc, *gateTy, ValueRange{actv, up}, ElemwiseKind::MUL, unit);
    Value out = rewriter.create<MatmulOp>(loc, *downTy, hidden,
                                          op.getDownWeight(), unit);
    rewriter.replaceOp(op, out);
    return success();
  }
};

struct ExpandCompComposites
    : impl::ExpandCompCompositesBase<ExpandCompComposites> {
  using impl::ExpandCompCompositesBase<
      ExpandCompComposites>::ExpandCompCompositesBase;

  void runOnOperation() override {
    RewritePatternSet patterns(&getContext());
    patterns.add<ExpandGatedMLP>(&getContext());
    if (failed(applyPatternsGreedily(getOperation(), std::move(patterns))))
      signalPassFailure();
  }
};
} // namespace
} // namespace mlir::s2c2
