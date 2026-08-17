//===- ComputeOps.h - S2C2 Compute ops --------------------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_COMPUTE_COMPUTEOPS_H
#define S2C2_COMPUTE_COMPUTEOPS_H

#include "s2c2/Compute/ComputeDialect.h"
#include "mlir/IR/Attributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Dialect.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"

#include "s2c2/Compute/ComputeEnums.h.inc"

#define GET_ATTRDEF_CLASSES
#include "s2c2/Compute/ComputeAttrs.h.inc"

#define GET_OP_CLASSES
#include "s2c2/Compute/ComputeOps.h.inc"

#endif // S2C2_COMPUTE_COMPUTEOPS_H
