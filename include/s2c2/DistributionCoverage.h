//===- DistributionCoverage.h - Shard tile coverage -------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_DISTRIBUTION_COVERAGE_H
#define S2C2_DISTRIBUTION_COVERAGE_H

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/OpDefinition.h"
#include "llvm/ADT/SmallVector.h"

namespace mlir {
namespace s2c2 {
namespace stor {

/// One rank's tile inside a global tensor. `tensorAxis` is -1 when the
/// sharding is replicated and the tile is the whole tensor.
struct LocalShard {
  bool replicated = false;
  int64_t tensorAxis = -1;
  int64_t meshSize = 0;
  SmallVector<int64_t, 4> offset;
  SmallVector<int64_t, 4> shape;
};

/// Tile of `rank` under the `shard.sharding` value. Emits a v0 diagnostic
/// on `emitOn` when the grid, the rank, or this rank's interval is illegal.
/// A legal partial tile does not by itself cover the axis.
FailureOr<LocalShard> localShardFor(Operation *emitOn, Value sharding,
                                    RankedTensorType global, int64_t rank);

/// Coverage of the whole sharding: out of bounds, then overlap, then a
/// gap. Replicated shardings cover without a partition axis.
LogicalResult diagnosePartition(Operation *emitOn, Value sharding,
                                RankedTensorType global, LocalShard &summary);

/// Group `stor.localize` by (global object, sharding, mesh). One global
/// cannot be placed on two meshes. Each group must name every rank of its
/// mesh once. Coverage stays in `diagnosePartition`.
LogicalResult checkLocalizeGroups(Operation *scope);

} // namespace stor
} // namespace s2c2
} // namespace mlir

#endif // S2C2_DISTRIBUTION_COVERAGE_H
