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
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/DialectImplementation.h"
#include "mlir/IR/OpImplementation.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/TypeSwitch.h"

#include <limits>

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

static LogicalResult
verifyMeshAxes(function_ref<InFlightDiagnostic()> emitError,
               DenseI64ArrayAttr shape, ArrayAttr axes) {
  if (!shape || shape.empty())
    return emitError() << "mesh shape must have positive extents";
  for (int64_t dim : shape.asArrayRef()) {
    if (dim <= 0)
      return emitError() << "mesh shape must have positive extents";
  }
  if (!axes || static_cast<int64_t>(axes.size()) != shape.size())
    return emitError() << "mesh axis names must match the mesh shape";
  llvm::SmallDenseSet<StringRef, 4> names;
  for (Attribute attr : axes) {
    auto name = llvm::dyn_cast<StringAttr>(attr);
    if (!name || name.getValue().empty())
      return emitError() << "mesh axis names must match the mesh shape";
    if (!names.insert(name.getValue()).second)
      return emitError() << "mesh axis names must be unique";
  }
  return success();
}

static LogicalResult
verifyTopologyShape(function_ref<InFlightDiagnostic()> emitError,
                    TopologyKind kind, DenseI64ArrayAttr shape) {
  if (!shape || shape.empty())
    return emitError() << "topology shape must have positive extents";
  for (int64_t dim : shape.asArrayRef()) {
    if (dim <= 0)
      return emitError() << "topology shape must have positive extents";
  }
  if (kind == TopologyKind::Line && shape.size() != 1)
    return emitError() << "line topology has one axis";
  if (kind == TopologyKind::Grid && shape.size() != 2)
    return emitError() << "grid topology has two axes";
  return success();
}

// True when a slower axis than `axis` has a non-zero coordinate. The full
// mesh product is not needed to name a device whose slower axes are zero.
static bool higherCoordinateUsed(ArrayRef<int64_t> coord, int axis) {
  for (int j = axis - 1; j >= 0; --j)
    if (coord[j] != 0)
      return true;
  return false;
}

// Row-major rank, last axis fastest. A coordinate whose rank fits in int64
// is accepted even when the product of the mesh extents does not.
static LogicalResult linearRank(ArrayRef<int64_t> shape, ArrayRef<int64_t> coord,
                                int64_t &rank) {
  const int64_t kMax = std::numeric_limits<int64_t>::max();
  int64_t value = 0;
  int64_t stride = 1;
  for (int i = static_cast<int>(shape.size()) - 1; i >= 0; --i) {
    if (stride <= 0 || coord[i] > (kMax - value) / stride)
      return failure();
    value += coord[i] * stride;
    if (!higherCoordinateUsed(coord, i))
      break;
    if (shape[i] <= 0 || stride > kMax / shape[i])
      return failure();
    stride *= shape[i];
  }
  rank = value;
  return success();
}

LogicalResult MeshType::verify(function_ref<InFlightDiagnostic()> emitError,
                               DenseI64ArrayAttr shape, ArrayAttr axes) {
  return verifyMeshAxes(emitError, shape, axes);
}

LogicalResult DeviceType::verify(function_ref<InFlightDiagnostic()> emitError,
                                 DenseI64ArrayAttr shape, ArrayAttr axes,
                                 DenseI64ArrayAttr coord, int64_t rank) {
  if (failed(verifyMeshAxes(emitError, shape, axes)))
    return failure();
  if (!coord || coord.size() != shape.size())
    return emitError() << "device coordinate is outside the mesh";
  for (int64_t i = 0; i < shape.size(); ++i) {
    if (coord[i] < 0 || coord[i] >= shape[i])
      return emitError() << "device coordinate is outside the mesh";
  }
  int64_t expected = 0;
  if (failed(linearRank(shape.asArrayRef(), coord.asArrayRef(), expected)) ||
      rank != expected)
    return emitError() << "device rank does not match its mesh coordinate";
  return success();
}

LogicalResult
TopologyType::verify(function_ref<InFlightDiagnostic()> emitError,
                     TopologyKind kind, DenseI64ArrayAttr shape) {
  return verifyTopologyShape(emitError, kind, shape);
}

LogicalResult MappingType::verify(function_ref<InFlightDiagnostic()> emitError,
                                  TopologyKind kind, DenseI64ArrayAttr shape) {
  return verifyTopologyShape(emitError, kind, shape);
}
