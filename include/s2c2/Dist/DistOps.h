//===- DistOps.h - S2C2 distribution ops ------------------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_DIST_DISTOPS_H
#define S2C2_DIST_DISTOPS_H

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "s2c2/Dist/DistTypes.h"

#define GET_OP_CLASSES
#include "s2c2/Dist/DistOps.h.inc"

#endif // S2C2_DIST_DISTOPS_H
