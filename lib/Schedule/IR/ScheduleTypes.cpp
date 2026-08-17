//===- ScheduleTypes.cpp - S2C2 Schedule types ------------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/Schedule/ScheduleTypes.h"

#include "s2c2/Schedule/ScheduleDialect.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/DialectImplementation.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace mlir::s2c2::sched;

#define GET_TYPEDEF_CLASSES
#include "s2c2/Schedule/ScheduleOpsTypes.cpp.inc"

void ScheduleDialect::registerTypes() {
  addTypes<
#define GET_TYPEDEF_LIST
#include "s2c2/Schedule/ScheduleOpsTypes.cpp.inc"
      >();
}
