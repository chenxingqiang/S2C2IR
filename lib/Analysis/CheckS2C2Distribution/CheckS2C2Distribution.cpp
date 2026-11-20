//===- CheckS2C2Distribution.cpp - Distribution checker ---------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// Connects upstream shard.sharding and dist.distribution to stor.localize.
// Two stor.materialize results in HBM are residencies of one object, not
// two mesh ranks. Mesh ranks come only from shard.grid.

#include "s2c2/DistributionCoverage.h"
#include "s2c2/Dist/DistOps.h"
#include "s2c2/S2C2Passes.h"
#include "s2c2/Storage/StorageOps.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Shard/IR/ShardOps.h"
#include "mlir/IR/BuiltinOps.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <algorithm>
#include <optional>

namespace mlir::s2c2 {
#define GEN_PASS_DEF_CHECKS2C2DISTRIBUTION
#include "s2c2/S2C2Passes.h.inc"

namespace {
struct TileKey {
  SmallVector<int64_t, 4> offset;
  SmallVector<int64_t, 4> shape;

  bool operator==(const TileKey &other) const {
    return offset == other.offset && shape == other.shape;
  }
  bool operator<(const TileKey &other) const {
    if (offset != other.offset)
      return std::lexicographical_compare(offset.begin(), offset.end(),
                                          other.offset.begin(),
                                          other.offset.end());
    return std::lexicographical_compare(shape.begin(), shape.end(),
                                        other.shape.begin(), other.shape.end());
  }
};

static int64_t moduleMeshSize(ModuleOp module) {
  std::optional<int64_t> size;
  bool conflict = false;
  module.walk([&](shard::GridOp grid) {
    int64_t n = 1;
    for (int64_t extent : grid.getShape()) {
      if (extent <= 0 || ShapedType::isDynamic(extent)) {
        conflict = true;
        return;
      }
      n *= extent;
    }
    if (!size)
      size = n;
    else if (*size != n)
      conflict = true;
  });
  if (conflict || !size)
    return 0;
  return *size;
}

static int hbmReplicas(func::FuncOp func) {
  DenseMap<Value, int> counts;
  func.walk([&](stor::MaterializeOp materialize) {
    auto buffer = llvm::cast<stor::BufferType>(materialize.getBuffer().getType());
    if (buffer.getSpace() != stor::Space::HBM)
      return;
    counts[materialize.getObject()]++;
  });
  int replicas = 0;
  for (const auto &entry : counts)
    replicas = std::max(replicas, entry.second);
  return replicas;
}

static TileKey tileOf(const stor::LocalShard &shard) {
  TileKey key;
  key.offset = shard.offset;
  key.shape = shard.shape;
  return key;
}

static LogicalResult distTiles(dist::DistributionOp distOp,
                               SmallVectorImpl<TileKey> &tiles) {
  for (Value shard : distOp.getShards()) {
    auto shardType = llvm::cast<dist::ShardType>(shard.getType());
    TileKey key;
    key.offset.assign(shardType.getOffset().asArrayRef().begin(),
                      shardType.getOffset().asArrayRef().end());
    key.shape.assign(shardType.getTileShape().asArrayRef().begin(),
                     shardType.getTileShape().asArrayRef().end());
    tiles.push_back(std::move(key));
  }
  return success();
}

static LogicalResult checkFunction(func::FuncOp func, ModuleOp module) {
  SmallVector<stor::LocalizeOp> localizes;
  func.walk([&](stor::LocalizeOp localize) { localizes.push_back(localize); });

  // No local shard: HBM buffers are residencies. A shard.grid in the module
  // does not turn those buffers into ranks.
  if (localizes.empty()) {
    if (hbmReplicas(func) == 0 && moduleMeshSize(module) == 0)
      return success();
    llvm::errs() << "distribution @" << func.getSymName()
                 << " hbm-replicas=" << hbmReplicas(func)
                 << " mesh-size=" << moduleMeshSize(module)
                 << " residencies-are-devices=no\n";
    return success();
  }

  // (global, sharding, mesh) is one group. Two globals in one function are
  // two groups. dist.distribution is only a tile cross-check.
  if (failed(stor::checkLocalizeGroups(func)))
    return failure();

  SmallVector<std::pair<Value, Value>> keys;
  SmallVector<SmallVector<stor::LocalizeOp>> groups;
  for (stor::LocalizeOp localize : localizes) {
    std::pair<Value, Value> key{localize.getGlobal(), localize.getSharding()};
    size_t index = 0;
    for (; index < keys.size(); ++index)
      if (keys[index] == key)
        break;
    if (index == keys.size()) {
      keys.push_back(key);
      groups.emplace_back();
    }
    groups[index].push_back(localize);
  }

  for (size_t index = 0; index < keys.size(); ++index) {
    Value global = keys[index].first;
    Value sharding = keys[index].second;
    auto globalType = dyn_cast<RankedTensorType>(
        llvm::cast<stor::ObjectType>(global.getType()).getPayloadType());
    if (!globalType)
      return func.emitOpError("local shape is not the shard tile");

    stor::LocalShard summary;
    if (failed(stor::diagnosePartition(func, sharding, globalType, summary)))
      return failure();

    SmallVector<TileKey> localTiles;
    for (stor::LocalizeOp localize : groups[index]) {
      FailureOr<stor::LocalShard> tile = stor::localShardFor(
          localize, sharding, globalType, localize.getRank());
      if (failed(tile))
        return failure();
      localTiles.push_back(tileOf(*tile));
    }

    bool matchedDistribution = false;
    bool tilesDiffer = false;
    func.walk([&](dist::DistributionOp distOp) {
      auto distGlobal =
          llvm::cast<dist::GlobalType>(distOp.getGlobal().getType())
              .getGlobalType();
      if (distGlobal != globalType)
        return;
      SmallVector<TileKey> distKeys;
      (void)distTiles(distOp, distKeys);
      SmallVector<TileKey> left = localTiles;
      SmallVector<TileKey> right = std::move(distKeys);
      llvm::sort(left);
      llvm::sort(right);
      if (left == right)
        matchedDistribution = true;
      else
        tilesDiffer = true;
    });
    if (tilesDiffer)
      return func.emitOpError("distribution tiles do not match local shards");

    llvm::errs() << "distribution @" << func.getSymName() << " coverage=";
    if (summary.replicated)
      llvm::errs() << "replicated:covered";
    else
      llvm::errs() << "axis" << summary.tensorAxis << ":covered";
    if (summary.meshSize == 1)
      llvm::errs() << " mesh-size=1";
    if (matchedDistribution)
      llvm::errs() << " distribution-stor=match";
    llvm::errs() << "\n";
  }
  return success();
}

struct CheckS2C2Distribution
    : impl::CheckS2C2DistributionBase<CheckS2C2Distribution> {
  using impl::CheckS2C2DistributionBase<
      CheckS2C2Distribution>::CheckS2C2DistributionBase;

  void runOnOperation() override {
    ModuleOp module = getOperation();
    bool failedCheck = false;
    for (func::FuncOp func : module.getOps<func::FuncOp>()) {
      if (failed(checkFunction(func, module)))
        failedCheck = true;
    }
    if (failedCheck)
      signalPassFailure();
  }
};
} // namespace
} // namespace mlir::s2c2
