//===- DistOps.cpp - S2C2 distribution ops ----------------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/Dist/DistOps.h"
#include "s2c2/Dist/DistDialect.h"

#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <utility>

#define GET_OP_CLASSES
#include "s2c2/Dist/DistOps.cpp.inc"

using namespace mlir;
using namespace mlir::s2c2::dist;

// Half-open ranges [start, end) on one axis.
// Judgment order for a sharded set:
//   1. a range outside [0, extent) is out of bounds;
//   2. two ranges that intersect overlap (touching endpoints do not);
//   3. any other union does not cover the global tensor.
using AxisRange = std::pair<int64_t, int64_t>;

static bool rangeExceeds(int64_t start, int64_t width, int64_t extent) {
  if (start < 0 || width <= 0 || extent <= 0)
    return true;
  if (start > extent)
    return true;
  return width > extent - start;
}

static LogicalResult checkShardFits(Operation *op, GlobalType globalTy,
                                    ShardType shardTy) {
  auto global = llvm::dyn_cast<RankedTensorType>(globalTy.getGlobalType());
  auto local = llvm::dyn_cast<RankedTensorType>(shardTy.getLocalType());
  if (!global || !local)
    return op->emitOpError("global and local payloads must be ranked tensors");
  if (global.getElementType() != local.getElementType())
    return op->emitOpError(
        "local tensor element type must match the global tensor");

  auto offset = shardTy.getOffset().asArrayRef();
  auto tile = shardTy.getTileShape().asArrayRef();
  if (static_cast<int64_t>(offset.size()) != global.getRank() ||
      static_cast<int64_t>(tile.size()) != global.getRank())
    return op->emitOpError(
        "shard offset and tile shape must have the global tensor rank");

  for (int64_t d = 0; d < global.getRank(); ++d) {
    if (rangeExceeds(offset[d], tile[d], global.getDimSize(d)))
      return op->emitOpError("shard range exceeds the global tensor");
  }

  if (shardTy.getPlacement() == Placement::Replicated) {
    for (int64_t d = 0; d < global.getRank(); ++d) {
      if (offset[d] != 0 || tile[d] != global.getDimSize(d))
        return op->emitOpError(
            "replicated shard must cover the whole global tensor");
    }
    return success();
  }

  int64_t axis = shardTy.getAxis();
  if (axis < 0 || axis >= global.getRank())
    return op->emitOpError("partition axis is out of range");
  for (int64_t d = 0; d < global.getRank(); ++d) {
    if (d == axis)
      continue;
    if (offset[d] != 0 || tile[d] != global.getDimSize(d))
      return op->emitOpError(
          "sharded shard must be full-extent off the partition axis");
  }
  return success();
}

// Sort by start, then walk once. An interval that begins before the
// covered end overlaps; a hole or a short union does not cover. Overlap
// is reported even when a hole is also present.
static LogicalResult verifyShardedCoverage(Operation *op, int64_t extent,
                                           ArrayRef<AxisRange> ranges) {
  SmallVector<AxisRange> ordered(ranges.begin(), ranges.end());
  llvm::sort(ordered, [](AxisRange lhs, AxisRange rhs) {
    if (lhs.first != rhs.first)
      return lhs.first < rhs.first;
    return lhs.second < rhs.second;
  });

  bool overlap = false;
  bool hole = false;
  int64_t covered = 0;
  for (AxisRange range : ordered) {
    if (range.first < covered)
      overlap = true;
    else if (range.first > covered)
      hole = true;
    if (range.second > covered)
      covered = range.second;
  }
  if (covered != extent)
    hole = true;
  if (overlap)
    return op->emitOpError("shards overlap");
  if (hole || ordered.empty())
    return op->emitOpError("shards do not cover the global tensor");
  return success();
}

LogicalResult ShardOp::verify() {
  return checkShardFits(getOperation(),
                        llvm::cast<GlobalType>(getGlobal().getType()),
                        llvm::cast<ShardType>(getShard().getType()));
}

LogicalResult LocalOp::verify() {
  auto shardTy = llvm::cast<ShardType>(getShard().getType());
  auto localTy = llvm::cast<LocalType>(getLocal().getType());
  if (localTy.getLocalType() != shardTy.getLocalType())
    return emitOpError("local tensor must match the shard");
  return success();
}

LogicalResult DistributionOp::verify() {
  if (getShards().empty())
    return emitOpError("distribution requires at least one shard");

  auto globalTy = llvm::cast<GlobalType>(getGlobal().getType());
  auto distTy = llvm::cast<DistributionType>(getDistribution().getType());
  if (distTy.getGlobalType() != globalTy.getGlobalType())
    return emitOpError(
        "distribution global tensor must match the global operand");

  auto global = llvm::cast<RankedTensorType>(globalTy.getGlobalType());
  SmallVector<ShardType> shardTypes;
  llvm::SmallDenseSet<Value, 8> seen;
  shardTypes.reserve(getShards().size());
  for (Value shard : getShards()) {
    if (!seen.insert(shard).second)
      return emitOpError("distribution lists the same shard more than once");
    auto shardOp = shard.getDefiningOp<ShardOp>();
    if (!shardOp || shardOp.getGlobal() != getGlobal())
      return emitOpError("shard is not part of this global tensor");
    auto shardTy = llvm::cast<ShardType>(shard.getType());
    if (shardTy.getPlacement() != distTy.getPlacement())
      return emitOpError("shard placement must match the distribution");
    if (distTy.getPlacement() == Placement::Sharded &&
        shardTy.getAxis() != distTy.getAxis())
      return emitOpError("shard partition axis must match the distribution");
    if (failed(checkShardFits(getOperation(), globalTy, shardTy)))
      return failure();
    shardTypes.push_back(shardTy);
  }

  if (distTy.getPlacement() == Placement::Replicated)
    return success();

  int64_t axis = distTy.getAxis();
  SmallVector<AxisRange> ranges;
  ranges.reserve(shardTypes.size());
  for (ShardType shardTy : shardTypes) {
    int64_t start = shardTy.getOffset().asArrayRef()[axis];
    int64_t width = shardTy.getTileShape().asArrayRef()[axis];
    ranges.push_back({start, start + width});
  }
  return verifyShardedCoverage(getOperation(), global.getDimSize(axis), ranges);
}

LogicalResult DeviceOp::verify() {
  auto meshTy = llvm::cast<MeshType>(getMesh().getType());
  auto deviceTy = llvm::cast<DeviceType>(getDevice().getType());
  if (deviceTy.getShape() != meshTy.getShape() ||
      deviceTy.getAxes() != meshTy.getAxes())
    return emitOpError("device is not on this mesh");
  return success();
}

LogicalResult PlaceOp::verify() {
  auto distOp = getDistribution().getDefiningOp<DistributionOp>();
  if (!distOp)
    return emitOpError("logical placement must be a dist.distribution");

  auto topoTy = llvm::cast<TopologyType>(getTopology().getType());
  auto meshTy = llvm::cast<MeshType>(getMesh().getType());
  auto mapTy = llvm::cast<MappingType>(getMapping().getType());
  if (topoTy.getKind() != mapTy.getKind() || topoTy.getShape() != mapTy.getShape())
    return emitOpError("mapping topology must match the hardware topology");
  if (topoTy.getKind() == TopologyKind::Line && meshTy.getShape().size() != 1)
    return emitOpError("topology does not match the device mesh");
  if (topoTy.getKind() == TopologyKind::Grid && meshTy.getShape().size() != 2)
    return emitOpError("topology does not match the device mesh");
  if (topoTy.getShape() != meshTy.getShape())
    return emitOpError("topology does not match the device mesh");

  auto expected = distOp.getShards();
  if (getShards().size() != expected.size() ||
      getDevices().size() != expected.size())
    return emitOpError(
        "placement must name each shard of the distribution once");
  llvm::SmallDenseSet<Value, 8> want;
  for (Value shard : expected)
    want.insert(shard);
  llvm::SmallDenseSet<Value, 8> seenShards;
  for (Value shard : getShards()) {
    if (!want.contains(shard) || !seenShards.insert(shard).second)
      return emitOpError(
          "placement must name each shard of the distribution once");
  }

  llvm::SmallDenseSet<Value, 8> seenDevices;
  llvm::SmallDenseSet<Attribute, 8> coords;
  for (Value device : getDevices()) {
    auto deviceTy = llvm::dyn_cast<DeviceType>(device.getType());
    if (!deviceTy)
      return emitOpError(
          "storage residency is not a device; a device has mesh coordinates");
    if (!seenDevices.insert(device).second)
      return emitOpError("placement lists the same device more than once");
    auto deviceOp = device.getDefiningOp<DeviceOp>();
    if (!deviceOp || deviceOp.getMesh() != getMesh() ||
        deviceTy.getShape() != meshTy.getShape() ||
        deviceTy.getAxes() != meshTy.getAxes())
      return emitOpError("device is not on this mesh");
    if (!coords.insert(deviceTy.getCoord()).second)
      return emitOpError("placement maps two shards to one device coordinate");
  }
  return success();
}
