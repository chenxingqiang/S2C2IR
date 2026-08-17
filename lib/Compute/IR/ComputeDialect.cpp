//===- ComputeDialect.cpp - S2C2 Compute dialect ----------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/Compute/ComputeDialect.h"
#include "s2c2/Compute/ComputeOps.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace mlir;
using namespace mlir::s2c2::comp;

#include "s2c2/Compute/ComputeOpsDialect.cpp.inc"
#include "s2c2/Compute/ComputeEnums.cpp.inc"

#define GET_ATTRDEF_CLASSES
#include "s2c2/Compute/ComputeAttrs.cpp.inc"

void ComputeDialect::registerAttributes() {
  addAttributes<
#define GET_ATTRDEF_LIST
#include "s2c2/Compute/ComputeAttrs.cpp.inc"
      >();
}

void ComputeDialect::initialize() {
  addOperations<
#define GET_OP_LIST
#include "s2c2/Compute/ComputeOps.cpp.inc"
      >();
  registerAttributes();
}
