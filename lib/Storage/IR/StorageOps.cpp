//===- StorageOps.cpp - S2C2 Storage ops ------------------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/Storage/StorageOps.h"
#include "s2c2/Storage/StorageDialect.h"

#include "s2c2/Storage/StorageInterfaces.cpp.inc"

#define GET_OP_CLASSES
#include "s2c2/Storage/StorageOps.cpp.inc"

using namespace mlir;
using namespace mlir::s2c2::stor;

Value mlir::s2c2::stor::getLogicalObject(Value buffer) {
  Operation *def = buffer.getDefiningOp();
  if (!def)
    return {};
  if (auto materialize = dyn_cast<MaterializeOp>(def))
    return materialize.getObject();
  if (auto transfer = dyn_cast<TransferOp>(def))
    return getLogicalObject(transfer.getSource());
  return {};
}

LogicalResult MaterializeOp::verify() {
  auto objTy = llvm::cast<ObjectType>(getObject().getType());
  auto bufTy = llvm::cast<BufferType>(getBuffer().getType());
  if (objTy.getPayloadType() != bufTy.getSourceType())
    return emitOpError("materialized buffer payload must match logical object");
  return success();
}

LogicalResult TransferOp::verify() {
  auto srcTy = llvm::cast<BufferType>(getSource().getType());
  auto dstTy = llvm::cast<BufferType>(getBuffer().getType());
  if (srcTy.getSourceType() != dstTy.getSourceType())
    return emitOpError(
        "transfer result payload must match the source buffer payload");
  return success();
}

LogicalResult PackOp::verify() {
  auto bufTy = llvm::cast<BufferType>(getBuffer().getType());
  if (getValue().getType() != bufTy.getSourceType())
    return emitOpError("packed tensor type must match buffer payload");
  return success();
}

LogicalResult UnpackOp::verify() {
  auto bufTy = llvm::cast<BufferType>(getBuffer().getType());
  if (getResult().getType() != bufTy.getSourceType())
    return emitOpError("unpacked tensor type must match buffer payload");
  return success();
}
