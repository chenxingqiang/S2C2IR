//===- DistTypes.h - S2C2 distribution types --------------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_DIST_DISTTYPES_H
#define S2C2_DIST_DISTTYPES_H

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Types.h"
#include "s2c2/Dist/DistDialect.h"

#include "s2c2/Dist/DistEnums.h.inc"

#define GET_TYPEDEF_CLASSES
#include "s2c2/Dist/DistOpsTypes.h.inc"

#endif // S2C2_DIST_DISTTYPES_H
