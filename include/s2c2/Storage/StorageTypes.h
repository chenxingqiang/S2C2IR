//===- StorageTypes.h - S2C2 Storage types ----------------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_STORAGE_STORAGETYPES_H
#define S2C2_STORAGE_STORAGETYPES_H

#include "mlir/IR/Attributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "s2c2/Storage/StorageDialect.h"

#include "s2c2/Storage/StorageEnums.h.inc"

#define GET_ATTRDEF_CLASSES
#include "s2c2/Storage/StorageAttrs.h.inc"

#define GET_TYPEDEF_CLASSES
#include "s2c2/Storage/StorageOpsTypes.h.inc"

#endif // S2C2_STORAGE_STORAGETYPES_H
