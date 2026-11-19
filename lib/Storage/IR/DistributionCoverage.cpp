//===- DistributionCoverage.cpp - Shard tile coverage -----------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Single-axis coverage uses the same order as dist.distribution:
//   1. a range outside [0, extent) is out of bounds;
//   2. two ranges that intersect overlap (touching endpoints do not);
//   3. any other union does not cover the global tensor.

#include "s2c2/DistributionCoverage.h"

#include "mlir/Dialect/Shard/IR/ShardOps.h"
#include "mlir/IR/SymbolTable.h"

#include <limits>
#include <utility>

using namespace mlir;
using namespace mlir::s2c2::stor;

namespace {
using AxisRange = std::pair<int64_t, int64_t>;

struct Split {
  bool replicated = false;
  int64_t tensorAxis = -1;
  int64_t gridAxis = -1;
};

static LogicalResult classify(shard::ShardingOp sharding, Operation *emitOn,
                              Split &out) {
  int64_t nonEmpty = 0;
  int64_t index = 0;
  for (auto sub : sharding.getSplitAxes().getAxes()) {
    if (!sub.empty()) {
      ++nonEmpty;
      if (sub.size() != 1)
        return emitOn->emitOpError(
            "sharding is not a v0 replicated or single-axis split");
      out.tensorAxis = index;
      out.gridAxis = sub.asArrayRef().front();
    }
    ++index;
  }
  if (nonEmpty == 0) {
    out.replicated = true;
    return success();
  }
  if (nonEmpty == 1)
    return success();
  return emitOn->emitOpError(
      "sharding is not a v0 replicated or single-axis split");
}

static std::optional<int64_t> meshProduct(ArrayRef<int64_t> shape) {
  if (shape.empty() || ShapedType::isDynamicShape(shape))
    return std::nullopt;
  int64_t n = 1;
  for (int64_t extent : shape) {
    if (extent <= 0 || n > std::numeric_limits<int64_t>::max() / extent)
      return std::nullopt;
    n *= extent;
  }
  return n;
}

static int64_t coordOnAxis(ArrayRef<int64_t> shape, int64_t linear,
                           int64_t axis) {
  int64_t rest = linear;
  int64_t coord = 0;
  for (int64_t i = static_cast<int64_t>(shape.size()) - 1; i >= 0; --i) {
    int64_t c = rest % shape[i];
    rest /= shape[i];
    if (i == axis)
      coord = c;
  }
  return coord;
}

struct Resolved {
  shard::ShardingOp sharding;
  shard::GridOp grid;
  Split split;
  SmallVector<int64_t, 4> shape;
  int64_t meshSize = 0;
  SmallVector<int64_t, 8> offsets;
};

static LogicalResult resolve(Operation *emitOn, Value shardingValue,
                             RankedTensorType global, Resolved &out) {
  auto sharding = shardingValue.getDefiningOp<shard::ShardingOp>();
  if (!sharding || !isa<shard::ShardingType>(shardingValue.getType()))
    return emitOn->emitOpError("expected a shard.sharding");
  if (!global || !global.hasStaticShape())
    return emitOn->emitOpError("local shape is not the shard tile");

  auto halo = sharding.getStaticHaloSizesAttr();
  if ((halo && !halo.empty()) || !sharding.getDynamicHaloSizes().empty())
    return emitOn->emitOpError("halo is outside distributed semantics v0");
  if (!sharding.getDynamicShardedDimsOffsets().empty())
    return emitOn->emitOpError(
        "dynamic shard offsets are outside distributed semantics v0");

  if (failed(classify(sharding, emitOn, out.split)))
    return failure();

  Operation *symbol = SymbolTable::lookupNearestSymbolFrom(
      emitOn, sharding.getGridAttr());
  auto grid = dyn_cast_or_null<shard::GridOp>(symbol);
  if (!grid)
    return emitOn->emitOpError("rank is outside the mesh");
  out.shape.assign(grid.getShape().begin(), grid.getShape().end());
  auto mesh = meshProduct(out.shape);
  if (!mesh)
    return emitOn->emitOpError("rank is outside the mesh");

  if (!out.split.replicated) {
    if (out.split.gridAxis < 0 ||
        out.split.gridAxis >= static_cast<int64_t>(out.shape.size()) ||
        out.split.tensorAxis < 0 || out.split.tensorAxis >= global.getRank())
      return emitOn->emitOpError(
          "sharding is not a v0 replicated or single-axis split");
  }

  auto offs = sharding.getStaticShardedDimsOffsetsAttr();
  if (offs && !offs.empty())
    out.offsets.assign(offs.asArrayRef().begin(), offs.asArrayRef().end());

  out.sharding = sharding;
  out.grid = grid;
  out.meshSize = *mesh;
  return success();
}

static LogicalResult intervalAt(Operation *emitOn, const Resolved &resolved,
                                RankedTensorType global, int64_t index,
                                AxisRange &range) {
  int64_t extent = global.getDimSize(resolved.split.tensorAxis);
  int64_t numShards = resolved.shape[resolved.split.gridAxis];
  int64_t start = 0;
  int64_t end = 0;
  if (resolved.offsets.empty()) {
    if (numShards <= 0 || extent % numShards != 0)
      return emitOn->emitOpError("shards do not cover the global tensor");
    int64_t tile = extent / numShards;
    start = index * tile;
    end = start + tile;
  } else {
    if (static_cast<int64_t>(resolved.offsets.size()) != numShards + 1 ||
        index < 0 || index + 1 >= static_cast<int64_t>(resolved.offsets.size()))
      return emitOn->emitOpError("shards do not cover the global tensor");
    start = resolved.offsets[index];
    end = resolved.offsets[index + 1];
  }
  if (start < 0 || end <= start || end > extent)
    return emitOn->emitOpError("shard range exceeds the global tensor");
  range = {start, end};
  return success();
}

static LogicalResult diagnoseRanges(Operation *emitOn, int64_t extent,
                                    ArrayRef<AxisRange> ranges) {
  for (AxisRange range : ranges) {
    if (range.first < 0 || range.second <= range.first || range.second > extent)
      return emitOn->emitOpError("shard range exceeds the global tensor");
  }

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
    return emitOn->emitOpError("shards overlap");
  if (hole || ordered.empty())
    return emitOn->emitOpError("shards do not cover the global tensor");
  return success();
}
} // namespace

FailureOr<LocalShard> mlir::s2c2::stor::localShardFor(Operation *emitOn,
                                                      Value sharding,
                                                      RankedTensorType global,
                                                      int64_t rank) {
  Resolved resolved;
  if (failed(resolve(emitOn, sharding, global, resolved)))
    return failure();
  if (rank < 0 || rank >= resolved.meshSize)
    return emitOn->emitOpError("rank is outside the mesh");

  LocalShard tile;
  tile.replicated = resolved.split.replicated;
  tile.tensorAxis = resolved.split.replicated ? -1 : resolved.split.tensorAxis;
  tile.meshSize = resolved.meshSize;
  tile.shape.reserve(global.getRank());
  tile.offset.reserve(global.getRank());
  for (int64_t dim = 0; dim < global.getRank(); ++dim) {
    tile.shape.push_back(global.getDimSize(dim));
    tile.offset.push_back(0);
  }
  if (tile.replicated)
    return tile;

  int64_t index =
      coordOnAxis(resolved.shape, rank, resolved.split.gridAxis);
  AxisRange range;
  if (failed(intervalAt(emitOn, resolved, global, index, range)))
    return failure();
  tile.offset[tile.tensorAxis] = range.first;
  tile.shape[tile.tensorAxis] = range.second - range.first;
  return tile;
}

LogicalResult mlir::s2c2::stor::diagnosePartition(Operation *emitOn,
                                                  Value sharding,
                                                  RankedTensorType global,
                                                  LocalShard &summary) {
  Resolved resolved;
  if (failed(resolve(emitOn, sharding, global, resolved)))
    return failure();
  summary.replicated = resolved.split.replicated;
  summary.tensorAxis =
      resolved.split.replicated ? -1 : resolved.split.tensorAxis;
  summary.meshSize = resolved.meshSize;
  summary.offset.clear();
  summary.shape.clear();
  if (summary.replicated)
    return success();

  int64_t numShards = resolved.shape[resolved.split.gridAxis];
  SmallVector<AxisRange> ranges;
  ranges.reserve(numShards);
  for (int64_t index = 0; index < numShards; ++index) {
    AxisRange range;
    if (failed(intervalAt(emitOn, resolved, global, index, range)))
      return failure();
    ranges.push_back(range);
  }
  return diagnoseRanges(emitOn, global.getDimSize(summary.tensorAxis), ranges);
}
