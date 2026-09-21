//===- StorToMemref.cpp - Convert stor/comm dialects to memref --*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/Comm/CommOps.h"
#include "s2c2/S2C2Passes.h"
#include "s2c2/Schedule/ScheduleOps.h"
#include "s2c2/Storage/StorageOps.h"
#include "s2c2/TargetSpaceMap.h"

#include "mlir/Dialect/Bufferization/IR/Bufferization.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/SCF/Transforms/Patterns.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/DialectConversion.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>

namespace mlir::s2c2 {
#define GEN_PASS_DEF_CONVERTSTORTOMEMREF
#define GEN_PASS_DEF_CONVERTCOMMTOMEMREF
#include "s2c2/S2C2Passes.h.inc"

using comm::BarrierOp;
using comm::CopyOp;
using comm::StreamOp;
using sched::WaitOp;
using stor::AllocOp;
using stor::BufferType;
using stor::DeallocOp;
using stor::MaterializeOp;
using stor::ObjectOp;
using stor::PackOp;
using stor::TransferOp;
using stor::UnpackOp;

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
    addConversion([](Type type) -> std::optional<Type> {
      if (llvm::isa<BufferType>(type))
        return std::nullopt;
      return type;
    });
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
    // Allocation only: contents remain unspecified (no copy).
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

struct ConvertUnpack : OpConversionPattern<UnpackOp> {
  using OpConversionPattern<UnpackOp>::OpConversionPattern;

  LogicalResult
  matchAndRewrite(UnpackOp op, OpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOpWithNewOp<bufferization::ToTensorOp>(
        op, op.getType(), adaptor.getBuffer(), /*restrict=*/true,
        /*writable=*/false);
    return success();
  }
};

struct ConvertPack : OpConversionPattern<PackOp> {
  using OpConversionPattern<PackOp>::OpConversionPattern;

  LogicalResult
  matchAndRewrite(PackOp op, OpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    auto bufTy = llvm::cast<BufferType>(op.getBuffer().getType());
    auto memrefTy = llvm::dyn_cast_if_present<MemRefType>(
        getTypeConverter()->convertType(bufTy));
    if (!memrefTy)
      return rewriter.notifyMatchFailure(op, "could not convert buffer type");
    Value tmp = rewriter.create<bufferization::ToMemrefOp>(
        op.getLoc(), memrefTy, adaptor.getValue());
    rewriter.create<memref::CopyOp>(op.getLoc(), tmp, adaptor.getBuffer());
    rewriter.eraseOp(op);
    return success();
  }
};

// Phase 2A blocking approximation: comm.copy / comm.stream become a
// synchronous memref.copy. This is *not* event-preserving comm lowering;
// Phase 2B must keep !sched.token → !async.token.
static LogicalResult rewriteAsMemrefCopy(Operation *op, Value src, Value dst,
                                         ConversionPatternRewriter &rewriter) {
  rewriter.create<memref::CopyOp>(op->getLoc(), src, dst);
  if (!op->use_empty())
    return rewriter.notifyMatchFailure(op, "completion token still has uses");
  rewriter.eraseOp(op);
  return success();
}

struct ConvertCopy : OpConversionPattern<CopyOp> {
  using OpConversionPattern<CopyOp>::OpConversionPattern;

  LogicalResult
  matchAndRewrite(CopyOp op, OpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    return rewriteAsMemrefCopy(op, adaptor.getSrc(), adaptor.getDst(), rewriter);
  }
};

struct ConvertStream : OpConversionPattern<StreamOp> {
  using OpConversionPattern<StreamOp>::OpConversionPattern;

  LogicalResult
  matchAndRewrite(StreamOp op, OpAdaptor adaptor,
                  ConversionPatternRewriter &rewriter) const override {
    return rewriteAsMemrefCopy(op, adaptor.getSrc(), adaptor.getDst(), rewriter);
  }
};

struct ConvertWait : OpConversionPattern<WaitOp> {
  using OpConversionPattern<WaitOp>::OpConversionPattern;

  LogicalResult
  matchAndRewrite(WaitOp op, OpAdaptor,
                  ConversionPatternRewriter &rewriter) const override {
    rewriter.eraseOp(op);
    return success();
  }
};

struct ConvertBarrier : OpConversionPattern<BarrierOp> {
  using OpConversionPattern<BarrierOp>::OpConversionPattern;

  LogicalResult
  matchAndRewrite(BarrierOp op, OpAdaptor,
                  ConversionPatternRewriter &rewriter) const override {
    rewriter.eraseOp(op);
    return success();
  }
};

static LogicalResult
runMemoryLowering(Operation *op, StringRef spaceMapSpec, MLIRContext *ctx) {
  SmallVector<Operation *> syncOps;
  op->walk([&](Operation *candidate) {
    if (isa<WaitOp, BarrierOp>(candidate))
      syncOps.push_back(candidate);
  });
  for (Operation *sync : llvm::reverse(syncOps))
    sync->erase();
  TargetSpaceMap map = TargetSpaceMap::getDefault();
  if (!spaceMapSpec.empty() &&
      failed(map.applyOverrides(spaceMapSpec, [&]() {
        return emitError(UnknownLoc::get(ctx), "invalid space-map: ");
      })))
    return failure();

  BufferToMemRefConverter converter(map);
  ConversionTarget target(*ctx);
  target.addLegalDialect<memref::MemRefDialect, func::FuncDialect,
                         bufferization::BufferizationDialect>();
  target.addLegalOp<ModuleOp>();
  target.addIllegalOp<AllocOp, DeallocOp, MaterializeOp, TransferOp, PackOp,
                      UnpackOp, CopyOp, StreamOp, WaitOp, BarrierOp>();

  RewritePatternSet patterns(ctx);
  patterns.add<ConvertAlloc, ConvertMaterialize, ConvertTransfer, ConvertDealloc,
               ConvertUnpack, ConvertPack, ConvertCopy, ConvertStream,
               ConvertWait, ConvertBarrier>(converter, ctx);
  scf::populateSCFStructuralTypeConversionsAndLegality(converter, patterns,
                                                       target);
  if (failed(applyPartialConversion(op, target, std::move(patterns))))
    return failure();

  SmallVector<ObjectOp> leftovers;
  op->walk([&](ObjectOp objectOp) { leftovers.push_back(objectOp); });
  for (ObjectOp objectOp : leftovers) {
    if (!objectOp->use_empty()) {
      objectOp.emitError("logical object still has uses after storage lowering");
      return failure();
    }
    objectOp.erase();
  }
  return success();
}

struct ConvertStorToMemref
    : impl::ConvertStorToMemrefBase<ConvertStorToMemref> {
  using impl::ConvertStorToMemrefBase<
      ConvertStorToMemref>::ConvertStorToMemrefBase;

  void runOnOperation() override {
    if (failed(runMemoryLowering(getOperation(), spaceMap, &getContext())))
      signalPassFailure();
  }
};

struct ConvertCommToMemref
    : impl::ConvertCommToMemrefBase<ConvertCommToMemref> {
  using impl::ConvertCommToMemrefBase<
      ConvertCommToMemref>::ConvertCommToMemrefBase;

  void runOnOperation() override {
    if (failed(runMemoryLowering(getOperation(), spaceMap, &getContext())))
      signalPassFailure();
  }
};
} // namespace
} // namespace mlir::s2c2
