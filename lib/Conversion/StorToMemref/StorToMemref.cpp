//===- StorToMemref.cpp - Convert stor dialect to memref --------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/S2C2Passes.h"
#include "s2c2/Storage/StorageOps.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/DialectConversion.h"

#include <optional>

namespace mlir::s2c2 {
#define GEN_PASS_DEF_CONVERTSTORTOMEMREF
#include "s2c2/S2C2Passes.h.inc"

using stor::AllocOp;
using stor::BufferType;
using stor::DeallocOp;
using stor::Space;

static IntegerAttr memorySpaceAttr(MLIRContext *ctx, Space space) {
  return IntegerAttr::get(IntegerType::get(ctx, 64),
                          static_cast<int64_t>(space));
}

static MemRefType convertBuffer(BufferType type) {
  auto tensor = llvm::cast<RankedTensorType>(type.getSourceType());
  return MemRefType::get(tensor.getShape(), tensor.getElementType(),
                         MemRefLayoutAttrInterface{},
                         memorySpaceAttr(type.getContext(), type.getSpace()));
}

namespace {
struct BufferToMemRefConverter : TypeConverter {
  BufferToMemRefConverter() {
    addConversion([](Type type) { return type; });
    addConversion([](BufferType type) -> std::optional<Type> {
      if (!isa<RankedTensorType>(type.getSourceType()))
        return std::nullopt;
      return convertBuffer(type);
    });
  }
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
    BufferToMemRefConverter converter;
    ConversionTarget target(getContext());
    target.addLegalDialect<memref::MemRefDialect, func::FuncDialect>();
    target.addLegalOp<ModuleOp>();
    target.addIllegalOp<AllocOp, DeallocOp>();

    RewritePatternSet patterns(&getContext());
    patterns.add<ConvertAlloc, ConvertDealloc>(converter, &getContext());
    if (failed(applyPartialConversion(getOperation(), target,
                                      std::move(patterns))))
      signalPassFailure();
  }
};
} // namespace
} // namespace mlir::s2c2
