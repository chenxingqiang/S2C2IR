//===- RankContext.h - Rank of a storage or collective op -------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_EXECUTIONMODEL_RANKCONTEXT_H
#define S2C2_EXECUTIONMODEL_RANKCONTEXT_H

#include "s2c2/ExecutionModel/HBGraph.h"

#include <optional>

namespace mlir::s2c2::exec {

/// Rank of the localize that owns this buffer, when the buffer is a shard
/// residency. An unlocalized object has no rank.
std::optional<int64_t> ownerRank(Value buffer);

/// Rank of one action. Unranked ops (sharding, object, yield) return nullopt.
std::optional<int64_t> rankOf(Operation *op);

/// One program order per rank. Textual order across ranks is not an edge.
/// After `sched.concurrent`, each rank's frontier is the end of its own task.
/// `sched.wait` joins only the ranks of the tokens it lists.
void buildRankOrder(func::FuncOp func, HBGraph &graph);

} // namespace mlir::s2c2::exec

#endif // S2C2_EXECUTIONMODEL_RANKCONTEXT_H
