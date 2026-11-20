//===- RankContext.cpp - Rank of a storage or collective op -----*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/ExecutionModel/RankContext.h"
#include "s2c2/ExecutionModel/CollectiveDependency.h"

#include "s2c2/Comm/CommOps.h"
#include "s2c2/Schedule/ScheduleOps.h"
#include "s2c2/Storage/StorageOps.h"

#include "mlir/Dialect/SCF/IR/SCF.h"

using namespace mlir;
using namespace mlir::s2c2;
using namespace mlir::s2c2::exec;
using comm::BarrierOp;
using comm::CopyOp;
using comm::StreamOp;
using sched::ConcurrentOp;
using sched::OverlapOp;
using sched::PipelineOp;
using sched::StageOp;
using sched::TaskOp;
using sched::WaitOp;
using stor::LocalizeOp;
using stor::MaterializeOp;
using stor::PackOp;
using stor::TransferOp;
using stor::UnpackOp;
using stor::getLogicalObject;

std::optional<int64_t> mlir::s2c2::exec::ownerRank(Value buffer) {
  Value obj = getLogicalObject(buffer);
  if (!obj)
    return std::nullopt;
  if (auto localize = obj.getDefiningOp<LocalizeOp>())
    return static_cast<int64_t>(localize.getRank());
  return std::nullopt;
}

std::optional<int64_t> mlir::s2c2::exec::rankOf(Operation *op) {
  if (!op)
    return std::nullopt;
  if (auto localize = dyn_cast<LocalizeOp>(op))
    return static_cast<int64_t>(localize.getRank());
  if (auto materialize = dyn_cast<MaterializeOp>(op))
    return ownerRank(materialize.getBuffer());
  if (auto pack = dyn_cast<PackOp>(op))
    return ownerRank(pack.getBuffer());
  if (auto unpack = dyn_cast<UnpackOp>(op))
    return ownerRank(unpack.getBuffer());
  if (auto stream = dyn_cast<StreamOp>(op))
    return ownerRank(stream.getSrc());
  if (auto copy = dyn_cast<CopyOp>(op))
    return ownerRank(copy.getSrc());
  if (auto transfer = dyn_cast<TransferOp>(op))
    return ownerRank(transfer.getBuffer());
  if (isa<WaitOp, BarrierOp>(op)) {
    for (Value token : op->getOperands()) {
      if (Operation *def = token.getDefiningOp())
        if (auto rank = rankOf(def))
          return rank;
    }
  }
  if (isV0Collective(op)) {
    if (auto unpack = op->getOperand(0).getDefiningOp<UnpackOp>())
      return ownerRank(unpack.getBuffer());
  }
  if (op->getName().getStringRef().starts_with("comp.")) {
    for (Value value : op->getOperands()) {
      if (auto unpack = value.getDefiningOp<UnpackOp>())
        if (auto rank = ownerRank(unpack.getBuffer()))
          return rank;
    }
  }
  return std::nullopt;
}

namespace {

using RankFrontier = llvm::DenseMap<int64_t, SmallVector<Operation *, 2>>;

void walkSeq(Block &block, RankFrontier &front, HBGraph &graph);

void overlay(RankFrontier &dst, const RankFrontier &src) {
  for (const auto &entry : src)
    dst[entry.first] = entry.second;
}

// A child copied the incoming frontier, so ranks it did not touch still hold
// the old ops. Publishing those would erase a sibling's update.
void overlayChanged(RankFrontier &dst, const RankFrontier &before,
                    const RankFrontier &after) {
  for (const auto &entry : after) {
    auto it = before.find(entry.first);
    if (it == before.end() || it->second != entry.second)
      dst[entry.first] = entry.second;
  }
}

void walkOp(Operation *op, RankFrontier &front, HBGraph &graph) {
  if (auto task = dyn_cast<TaskOp>(op)) {
    if (!task.getBody().empty())
      walkSeq(task.getBody().front(), front, graph);
    return;
  }
  if (auto conc = dyn_cast<ConcurrentOp>(op)) {
    if (conc.getBody().empty())
      return;
    RankFrontier joined = front;
    for (Operation &child : conc.getBody().front().without_terminator()) {
      RankFrontier copy = front;
      walkOp(&child, copy, graph);
      overlayChanged(joined, front, copy);
    }
    front = std::move(joined);
    return;
  }
  if (auto pipe = dyn_cast<PipelineOp>(op)) {
    if (pipe.getBody().empty())
      return;
    for (StageOp stage : pipe.getBody().front().getOps<StageOp>()) {
      if (!stage.getBody().empty())
        walkSeq(stage.getBody().front(), front, graph);
    }
    return;
  }
  if (auto overlap = dyn_cast<OverlapOp>(op)) {
    RankFrontier before = front;
    RankFrontier compute = before;
    RankFrontier communicate = before;
    if (!overlap.getCompute().empty())
      walkSeq(overlap.getCompute().front(), compute, graph);
    if (!overlap.getCommunicate().empty())
      walkSeq(overlap.getCommunicate().front(), communicate, graph);
    overlayChanged(front, before, compute);
    overlayChanged(front, before, communicate);
    return;
  }
  if (auto forOp = dyn_cast<scf::ForOp>(op)) {
    if (!forOp.getBodyRegion().empty()) {
      RankFrontier copy = front;
      walkSeq(*forOp.getBody(), copy, graph);
    }
    return;
  }
  if (auto ifOp = dyn_cast<scf::IfOp>(op)) {
    RankFrontier joined = front;
    if (Block *thenB = ifOp.thenBlock()) {
      RankFrontier copy = front;
      walkSeq(*thenB, copy, graph);
      overlay(joined, copy);
    }
    if (Block *elseB = ifOp.elseBlock()) {
      RankFrontier copy = front;
      walkSeq(*elseB, copy, graph);
      overlay(joined, copy);
    }
    front = std::move(joined);
    return;
  }
  if (auto sw = dyn_cast<scf::IndexSwitchOp>(op)) {
    RankFrontier joined = front;
    for (Region &region : sw->getRegions()) {
      if (region.empty())
        continue;
      RankFrontier copy = front;
      walkSeq(region.front(), copy, graph);
      overlay(joined, copy);
    }
    front = std::move(joined);
    return;
  }

  std::optional<int64_t> rank = rankOf(op);
  if (!rank) {
    if (isa<WaitOp, BarrierOp>(op)) {
      for (Value token : op->getOperands())
        if (Operation *def = token.getDefiningOp())
          graph.addEdge(def, op);
    }
    return;
  }
  graph.addEdges(front.lookup(*rank), op);
  if (isa<WaitOp, BarrierOp>(op)) {
    for (Value token : op->getOperands())
      if (Operation *def = token.getDefiningOp())
        graph.addEdge(def, op);
  }
  front[*rank].assign({op});
}

void walkSeq(Block &block, RankFrontier &front, HBGraph &graph) {
  for (Operation &op : block.without_terminator())
    walkOp(&op, front, graph);
}

} // namespace

void mlir::s2c2::exec::buildRankOrder(func::FuncOp func, HBGraph &graph) {
  if (func.getBody().empty())
    return;
  RankFrontier front;
  walkSeq(func.getBody().front(), front, graph);
}
