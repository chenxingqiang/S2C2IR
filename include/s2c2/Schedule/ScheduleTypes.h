//===- ScheduleTypes.h - S2C2 Schedule types --------------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_SCHEDULE_SCHEDULETYPES_H
#define S2C2_SCHEDULE_SCHEDULETYPES_H

#include "mlir/IR/BuiltinTypes.h"
#include "s2c2/Schedule/ScheduleDialect.h"

#define GET_TYPEDEF_CLASSES
#include "s2c2/Schedule/ScheduleOpsTypes.h.inc"

#endif // S2C2_SCHEDULE_SCHEDULETYPES_H
