//===- StorageTypes.cpp - S2C2 Storage types --------------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/Storage/StorageTypes.h"

#include "s2c2/Storage/StorageDialect.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/IR/OpImplementation.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace mlir;
using namespace mlir::s2c2::stor;

#include "s2c2/Storage/StorageEnums.cpp.inc"

#define GET_ATTRDEF_CLASSES
#include "s2c2/Storage/StorageAttrs.cpp.inc"

#define GET_TYPEDEF_CLASSES
#include "s2c2/Storage/StorageOpsTypes.cpp.inc"

void StorageDialect::registerTypes() {
  addTypes<
#define GET_TYPEDEF_LIST
#include "s2c2/Storage/StorageOpsTypes.cpp.inc"
      >();
}

void StorageDialect::registerAttributes() {
  addAttributes<
#define GET_ATTRDEF_LIST
#include "s2c2/Storage/StorageAttrs.cpp.inc"
      >();
}

LogicalResult ObjectType::verify(
    function_ref<InFlightDiagnostic()> emitError, Type payloadType) {
  if (!::llvm::isa<RankedTensorType>(payloadType))
    return emitError() << "logical object payload must be a ranked tensor";
  return success();
}

LogicalResult BufferType::verify(
    function_ref<InFlightDiagnostic()> emitError, Type sourceType, Space) {
  if (!::llvm::isa<RankedTensorType>(sourceType))
    return emitError() << "buffer payload must be a ranked tensor";
  return success();
}
