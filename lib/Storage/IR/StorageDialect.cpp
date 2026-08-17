//===- StorageDialect.cpp - S2C2 Storage dialect ----------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/Storage/StorageDialect.h"
#include "s2c2/Storage/StorageOps.h"
#include "s2c2/Storage/StorageTypes.h"

using namespace mlir;
using namespace mlir::s2c2::stor;

#include "s2c2/Storage/StorageOpsDialect.cpp.inc"

void StorageDialect::initialize() {
  addOperations<
#define GET_OP_LIST
#include "s2c2/Storage/StorageOps.cpp.inc"
      >();
  registerTypes();
  registerAttributes();
}
