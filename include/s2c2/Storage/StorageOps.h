//===- StorageOps.h - S2C2 Storage ops --------------------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_STORAGE_STORAGEOPS_H
#define S2C2_STORAGE_STORAGEOPS_H

#include "s2c2/Storage/StorageTypes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/Dialect.h"
#include "mlir/IR/OpDefinition.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"

#include "s2c2/Storage/StorageInterfaces.h.inc"

#define GET_OP_CLASSES
#include "s2c2/Storage/StorageOps.h.inc"

#endif // S2C2_STORAGE_STORAGEOPS_H
