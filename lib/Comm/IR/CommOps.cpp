//===- CommOps.cpp - S2C2 Communication ops ---------------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/Comm/CommOps.h"
#include "s2c2/Comm/CommDialect.h"

#define GET_OP_CLASSES
#include "s2c2/Comm/CommOps.cpp.inc"

using namespace mlir;
using namespace mlir::s2c2::comm;
using mlir::s2c2::stor::BufferType;

static LogicalResult verifyBufferPair(Operation *op, Value src, Value dst,
                                      bool requireDifferentSpaces) {
  auto srcTy = llvm::dyn_cast<BufferType>(src.getType());
  auto dstTy = llvm::dyn_cast<BufferType>(dst.getType());
  if (!srcTy || !dstTy)
    return op->emitOpError("operands must be storage buffers");
  if (srcTy.getSourceType() != dstTy.getSourceType())
    return op->emitOpError(
        "source and destination buffer payload types must match");
  if (requireDifferentSpaces && srcTy.getSpace() == dstTy.getSpace())
    return op->emitOpError("source and destination storage spaces must differ");
  return success();
}

LogicalResult CopyOp::verify() {
  return verifyBufferPair(getOperation(), getSrc(), getDst(),
                          /*requireDifferentSpaces=*/false);
}

LogicalResult StreamOp::verify() {
  return verifyBufferPair(getOperation(), getSrc(), getDst(),
                          /*requireDifferentSpaces=*/true);
}
