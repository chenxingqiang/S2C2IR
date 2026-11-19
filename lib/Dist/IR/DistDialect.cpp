//===- DistDialect.cpp - S2C2 distribution dialect --------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/Dist/DistDialect.h"
#include "s2c2/Dist/DistOps.h"
#include "s2c2/Dist/DistTypes.h"

using namespace mlir;
using namespace mlir::s2c2::dist;

#include "s2c2/Dist/DistOpsDialect.cpp.inc"

void DistDialect::initialize() {
  addOperations<
#define GET_OP_LIST
#include "s2c2/Dist/DistOps.cpp.inc"
      >();
  registerTypes();
}
