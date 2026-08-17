//===- ScheduleDialect.cpp - S2C2 Schedule dialect --------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/Schedule/ScheduleDialect.h"
#include "s2c2/Schedule/ScheduleOps.h"
#include "s2c2/Schedule/ScheduleTypes.h"

using namespace mlir;
using namespace mlir::s2c2::sched;

#include "s2c2/Schedule/ScheduleOpsDialect.cpp.inc"

void ScheduleDialect::initialize() {
  addOperations<
#define GET_OP_LIST
#include "s2c2/Schedule/ScheduleOps.cpp.inc"
      >();
  registerTypes();
}
