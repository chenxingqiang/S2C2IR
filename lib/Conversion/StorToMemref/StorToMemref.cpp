//===- StorToMemref.cpp - Convert stor dialect to memref --------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/S2C2Passes.h"
#include "s2c2/Storage/StorageOps.h"
#include "s2c2/TargetSpaceMap.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/DialectConversion.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>

namespace mlir::s2c2 {
#define GEN_PASS_DEF_CONVERTSTORTOMEMREF
#include "s2c2/S2C2Passes.h.inc"

using stor::AllocOp;
using stor::BufferType;
using stor::DeallocOp;
using stor::MaterializeOp;
using stor::ObjectOp;
using stor::Space;
using stor::TransferOp;

static IntegerAttr memorySpaceAttr(MLIRContext *ctx, int64_t spaceId) {
  return IntegerAttr::get(IntegerType::get(ctx, 64), spaceId);
}

static MemRefType convertBuffer(BufferType type, const TargetSpaceMap &map) {
  auto tensor = llvm::cast<RankedTensorType>(type.getSourceType());
  return MemRefType::get(tensor.getShape(), tensor.getElementType(),
                         MemRefLayoutAttrInterface{},
                         memorySpaceAttr(type.getContext(),
                                         map.lookup(type.getSpace())));
}

namespace {
struct BufferToMemRefConverter : TypeConverter {
  explicit BufferToMemRefConverter(const TargetSpaceMap &map) : map(map) {
    addConversion([](Type type) { return type; });
    addConversion([&](BufferType type) -> std::optional<Type> {
      if (!llvm::isa<RankedTensorType>(type.getSourceType()))
        return std::nullopt;
      return convertBuffer(type, this->map);
    });
  }

  const TargetSpaceMap &map;
};

struct ConvertAlloc : OpConversionPattern<AllocOp> {
  using OpConversionPattern<AllocOp>::OpConversionPattern;

  LogicalResult
  matchAndRewrite(AllocOp op, OpAdaptor,
                  ConversionPatternRewriter &rewriter) const override {
    auto bufTy = llvm::cast<BufferType>(op.getType());
    auto memrefTy = llvm::dyn_cast_if_present<MemRefType>(
        getTypeConverter()->convertType(bufTy));
    if (!memrefTy)
      return rewriter.notifyMatchFailure(op, "could not convert buffer type");
    rewriter.replaceOpWithNewOp<memref::AllocOp>(op, memrefTy);
    return success();
  }
};

struct ConvertMaterialize : OpConversionPattern<MaterializeOp> {
  using OpConversionPattern<MaterializeOp>::OpConversionPattern;

  LogicalResult
  matchAndRewrite(MaterializeOp op, OpAdaptor,
                  ConversionPatternRewriter &rewriter) const override {
    auto bufTy = llvm::cast<BufferType>(op.getType());
    auto memrefTy = llvm::dyn_cast_if_present<MemRefType>(
        getTypeConverter()->convertType(bufTy));
    if (!memrefTy)
      return rewriter.notifyMatchFailure(op, "could not convert buffer type");
    rewriter.replaceOpWithNewOp<memref::AllocOp>(op, memrefTy);
    return success();
  }
};

struct ConvertTransfer : OpConversionPattern<TransferOp> {
  using OpConversionPattern<TransferOp>::OpConversionPattern;

  LogicalResult
  matchAndRewrite(TransferOp op, OpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    auto bufTy = llvm::cast<BufferType>(op.getType());
    auto memrefTy = llvm::dyn_cast_if_present<MemRefType>(
        getTypeConverter()->convertType(bufTy));
    if (!memrefTy)
      return rewriter.notifyMatchFailure(op, "could not convert buffer type");
    Value dst = rewriter.create<memref::AllocOp>(op.getLoc(), memrefTy);
    rewriter.create<memref::CopyOp>(op.getLoc(), adaptor.getSource(), dst);
    rewriter.replaceOp(op, dst);
    return success();
  }
};

struct ConvertDealloc : OpConversionPattern<DeallocOp> {
  using OpConversionPattern<DeallocOp>::OpConversionPattern;

  LogicalResult
  matchAndRewrite(DeallocOp op, OpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<memref::DeallocOp>(op, adaptor.getBuffer());
    return success();
  }
};

struct ConvertStorToMemref
    : impl::ConvertStorToMemrefBase<ConvertStorToMemref> {
  using impl::ConvertStorToMemrefBase<
      ConvertStorToMemref>::ConvertStorToMemrefBase;

  void runOnOperation() override {
    TargetSpaceMap map = TargetSpaceMap::getDefault();
    if (!spaceMap.empty() &&
        failed(map.applyOverrides(spaceMap, [&]() {
          return emitError(UnknownLoc::get(&getContext()),
                           "invalid space-map: ");
        }))) {
      signalPassFailure();
      return;
    }

    BufferToMemRefConverter converter(map);
    ConversionTarget target(getContext());
    target.addLegalDialect<memref::MemRefDialect, func::FuncDialect>();
    target.addLegalOp<ModuleOp>();
    // ObjectOp stays legal until residencies are converted, then unused
    // identities are erased.
    target.addIllegalOp<AllocOp, DeallocOp, MaterializeOp, TransferOp>();

    RewritePatternSet patterns(&getContext());
    patterns.add<ConvertAlloc, ConvertMaterialize, ConvertTransfer,
                 ConvertDealloc>(converter, &getContext());
    if (failed(applyPartialConversion(getOperation(), target,
                                      std::move(patterns)))) {
      signalPassFailure();
      return;
    }

    SmallVector<ObjectOp> leftovers;
    getOperation()->walk([&](ObjectOp op) { leftovers.push_back(op); });
    for (ObjectOp op : leftovers) {
      if (!op->use_empty()) {
        op.emitError("logical object still has uses after storage lowering");
        signalPassFailure();
        return;
      }
      op.erase();
    }
  }
};
} // namespace
} // namespace mlir::s2c2
