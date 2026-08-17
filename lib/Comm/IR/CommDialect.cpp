//===- CommDialect.cpp - S2C2 Communication dialect -------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/Comm/CommDialect.h"
#include "s2c2/Comm/CommOps.h"
#include "s2c2/Schedule/ScheduleDialect.h"
#include "s2c2/Storage/StorageDialect.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace mlir;
using namespace mlir::s2c2::comm;

#include "s2c2/Comm/CommOpsDialect.cpp.inc"
#include "s2c2/Comm/CommEnums.cpp.inc"

#define GET_ATTRDEF_CLASSES
#include "s2c2/Comm/CommAttrs.cpp.inc"

void CommDialect::registerAttributes() {
  addAttributes<
#define GET_ATTRDEF_LIST
#include "s2c2/Comm/CommAttrs.cpp.inc"
      >();
}

void CommDialect::initialize() {
  addOperations<
#define GET_OP_LIST
#include "s2c2/Comm/CommOps.cpp.inc"
      >();
  registerAttributes();
}
