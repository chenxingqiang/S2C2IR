//===- DistTypes.cpp - S2C2 distribution types ------------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/Dist/DistTypes.h"

#include "s2c2/Dist/DistDialect.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/IR/OpImplementation.h"
#include "llvm/ADT/TypeSwitch.h"

using namespace mlir;
using namespace mlir::s2c2::dist;

#include "s2c2/Dist/DistEnums.cpp.inc"

#define GET_TYPEDEF_CLASSES
#include "s2c2/Dist/DistOpsTypes.cpp.inc"

namespace {
LogicalResult verifyPositiveTensor(function_ref<InFlightDiagnostic()> emitError,
                                   Type type, StringRef what) {
  auto tensor = llvm::dyn_cast<RankedTensorType>(type);
  if (!tensor || !tensor.hasStaticShape() || tensor.getRank() < 1)
    return emitError() << what
                       << " must be a ranked static tensor with positive extents";
  for (int64_t dim : tensor.getShape()) {
    if (dim <= 0)
      return emitError() << what
                         << " must be a ranked static tensor with positive extents";
  }
  return success();
}
} // namespace

void DistDialect::registerTypes() {
  addTypes<
#define GET_TYPEDEF_LIST
#include "s2c2/Dist/DistOpsTypes.cpp.inc"
      >();
}

LogicalResult GlobalType::verify(function_ref<InFlightDiagnostic()> emitError,
                                 Type globalType) {
  return verifyPositiveTensor(emitError, globalType, "global tensor");
}

LogicalResult LocalType::verify(function_ref<InFlightDiagnostic()> emitError,
                                Type localType) {
  return verifyPositiveTensor(emitError, localType, "local tensor");
}

LogicalResult ShardType::verify(function_ref<InFlightDiagnostic()> emitError,
                                Type localType, Placement placement,
                                int64_t axis, DenseI64ArrayAttr offset,
                                DenseI64ArrayAttr tileShape) {
  if (failed(verifyPositiveTensor(emitError, localType, "shard local tensor")))
    return failure();
  auto local = llvm::cast<RankedTensorType>(localType);
  if (!offset || !tileShape)
    return emitError() << "shard offset and tile shape are required";
  if (static_cast<int64_t>(offset.size()) != local.getRank() ||
      static_cast<int64_t>(tileShape.size()) != local.getRank())
    return emitError()
           << "shard offset and tile shape must match the local tensor rank";
  for (int64_t d = 0; d < local.getRank(); ++d) {
    if (offset[d] < 0)
      return emitError() << "shard offset must be non-negative";
    if (tileShape[d] <= 0)
      return emitError() << "tile shape must be positive";
    if (tileShape[d] != local.getDimSize(d))
      return emitError() << "shard tile shape must match the local tensor";
  }
  if (placement == Placement::Replicated) {
    if (axis != -1)
      return emitError() << "replicated shard has no partition axis";
    return success();
  }
  if (axis < 0 || axis >= local.getRank())
    return emitError() << "partition axis is out of range";
  return success();
}

LogicalResult
DistributionType::verify(function_ref<InFlightDiagnostic()> emitError,
                         Type globalType, Placement placement, int64_t axis) {
  if (failed(verifyPositiveTensor(emitError, globalType, "global tensor")))
    return failure();
  auto global = llvm::cast<RankedTensorType>(globalType);
  if (placement == Placement::Replicated) {
    if (axis != -1)
      return emitError() << "replicated distribution has no partition axis";
    return success();
  }
  if (axis < 0 || axis >= global.getRank())
    return emitError() << "partition axis is out of range";
  return success();
}
