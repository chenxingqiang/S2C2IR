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
