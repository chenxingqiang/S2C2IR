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
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"

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

namespace {

std::optional<int64_t> taskRank(TaskOp task) {
  std::optional<int64_t> found;
  task.walk([&](Operation *op) {
    if (op == task.getOperation() || found)
      return;
    if (auto pack = dyn_cast<PackOp>(op))
      found = ownerRank(pack.getBuffer());
    else if (auto unpack = dyn_cast<UnpackOp>(op))
      found = ownerRank(unpack.getBuffer());
    else if (isV0Collective(op)) {
      if (auto consumed = op->getOperand(0).getDefiningOp<UnpackOp>())
        found = ownerRank(consumed.getBuffer());
    }
  });
  return found;
}

// Every ranked operand must agree. The first operand does not own the op.
std::optional<int64_t> compRank(Operation *op) {
  std::optional<int64_t> seen;
  for (Value value : op->getOperands()) {
    std::optional<int64_t> rank;
    if (auto unpack = value.getDefiningOp<UnpackOp>())
      rank = ownerRank(unpack.getBuffer());
    else if (Operation *def = value.getDefiningOp())
      if (def->getName().getStringRef().starts_with("comp."))
        rank = compRank(def);
    if (!rank)
      continue;
    if (!seen)
      seen = rank;
    else if (*seen != *rank)
      return std::nullopt;
  }
  return seen;
}

} // namespace

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
  if (auto task = dyn_cast<TaskOp>(op))
    return taskRank(task);
  if (auto wait = dyn_cast<WaitOp>(op)) {
    // One rank only when every token agrees. A multi-rank wait is not
    // owned by the first token.
    std::optional<int64_t> seen;
    for (Value token : wait.getTokens()) {
      std::optional<int64_t> rank;
      if (auto task = token.getDefiningOp<TaskOp>())
        rank = taskRank(task);
      else if (Operation *def = token.getDefiningOp())
        rank = rankOf(def);
      if (!rank)
        continue;
      if (!seen)
        seen = rank;
      else if (*seen != *rank)
        return std::nullopt;
    }
    return seen;
  }
  if (isa<BarrierOp>(op)) {
    for (Value token : op->getOperands()) {
      if (auto task = token.getDefiningOp<TaskOp>())
        if (auto rank = taskRank(task))
          return rank;
      if (Operation *def = token.getDefiningOp())
        if (auto rank = rankOf(def))
          return rank;
    }
  }
  if (isV0Collective(op)) {
    if (auto unpack = op->getOperand(0).getDefiningOp<UnpackOp>())
      return ownerRank(unpack.getBuffer());
  }
  if (op->getName().getStringRef().starts_with("comp."))
    return compRank(op);
  return std::nullopt;
}

namespace {

using RankFrontier = llvm::DenseMap<int64_t, SmallVector<Operation *, 2>>;

void walkSeq(Block &block, RankFrontier &front, HBGraph &graph);

void unionInto(SmallVector<Operation *, 2> &dst, ArrayRef<Operation *> src) {
  for (Operation *op : src)
    if (!llvm::is_contained(dst, op))
      dst.push_back(op);
}

RankFrontier unionFrontiers(ArrayRef<RankFrontier> branches) {
  RankFrontier joined;
  SmallVector<int64_t> ranks;
  for (const RankFrontier &branch : branches) {
    for (const auto &entry : branch)
      if (!llvm::is_contained(ranks, entry.first))
        ranks.push_back(entry.first);
  }
  for (int64_t rank : ranks) {
    auto &dst = joined[rank];
    for (const RankFrontier &branch : branches) {
      auto it = branch.find(rank);
      if (it != branch.end())
        unionInto(dst, it->second);
    }
  }
  return joined;
}

// A lane copied the incoming frontier. Only ranks it changed contribute
// exits; untouched ranks still hold the pre-overlap ops.
bool rankChanged(const RankFrontier &before, const RankFrontier &after,
                 int64_t rank) {
  auto afterIt = after.find(rank);
  if (afterIt == after.end())
    return false;
  auto beforeIt = before.find(rank);
  return beforeIt == before.end() || beforeIt->second != afterIt->second;
}

void walkOp(Operation *op, RankFrontier &front, HBGraph &graph) {
  if (auto task = dyn_cast<TaskOp>(op)) {
    // The task token is the completion event. The last body op is not.
    RankFrontier before = front;
    if (!task.getBody().empty())
      walkSeq(task.getBody().front(), front, graph);
    SmallVector<std::pair<int64_t, SmallVector<Operation *, 2>>> changed;
    for (const auto &entry : front) {
      auto it = before.find(entry.first);
      if (it != before.end() && it->second == entry.second)
        continue;
      changed.push_back({entry.first, entry.second});
    }
    for (auto &entry : changed) {
      graph.addEdges(entry.second, task);
      front[entry.first].assign({task.getOperation()});
    }
    return;
  }
  if (auto conc = dyn_cast<ConcurrentOp>(op)) {
    if (conc.getBody().empty())
      return;
    llvm::DenseMap<int64_t, SmallVector<Operation *, 2>> exits;
    for (Operation &child : conc.getBody().front().without_terminator()) {
      RankFrontier copy = front;
      walkOp(&child, copy, graph);
      for (const auto &entry : copy) {
        auto it = front.find(entry.first);
        if (it != front.end() && it->second == entry.second)
          continue;
        unionInto(exits[entry.first], entry.second);
      }
    }
    for (const auto &entry : exits)
      front[entry.first] = entry.second;
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
    // Both lanes run. A changed rank keeps every changed lane's exit.
    RankFrontier before = front;
    RankFrontier compute = before;
    RankFrontier communicate = before;
    if (!overlap.getCompute().empty())
      walkSeq(overlap.getCompute().front(), compute, graph);
    if (!overlap.getCommunicate().empty())
      walkSeq(overlap.getCommunicate().front(), communicate, graph);
    llvm::SmallDenseSet<int64_t, 4> ranks;
    for (const RankFrontier &lane : {compute, communicate})
      for (const auto &entry : lane)
        ranks.insert(entry.first);
    for (int64_t rank : ranks) {
      bool computeChanged = rankChanged(before, compute, rank);
      bool communicateChanged = rankChanged(before, communicate, rank);
      if (!computeChanged && !communicateChanged)
        continue;
      front[rank].clear();
      if (computeChanged)
        unionInto(front[rank], compute.find(rank)->second);
      if (communicateChanged)
        unionInto(front[rank], communicate.find(rank)->second);
    }
    return;
  }
  if (auto forOp = dyn_cast<scf::ForOp>(op)) {
    if (forOp.getBodyRegion().empty())
      return;
    RankFrontier copy = front;
    walkSeq(*forOp.getBody(), copy, graph);
    for (const auto &entry : copy)
      unionInto(front[entry.first], entry.second);
    return;
  }
  if (auto ifOp = dyn_cast<scf::IfOp>(op)) {
    SmallVector<RankFrontier, 2> branches;
    if (Block *thenB = ifOp.thenBlock()) {
      RankFrontier copy = front;
      walkSeq(*thenB, copy, graph);
      branches.push_back(std::move(copy));
    }
    if (Block *elseB = ifOp.elseBlock()) {
      RankFrontier copy = front;
      walkSeq(*elseB, copy, graph);
      branches.push_back(std::move(copy));
    } else {
      branches.push_back(front);
    }
    if (!branches.empty())
      front = unionFrontiers(branches);
    return;
  }
  if (auto sw = dyn_cast<scf::IndexSwitchOp>(op)) {
    SmallVector<RankFrontier, 4> branches;
    for (Region &region : sw->getRegions()) {
      if (region.empty())
        continue;
      RankFrontier copy = front;
      walkSeq(region.front(), copy, graph);
      branches.push_back(std::move(copy));
    }
    if (!branches.empty())
      front = unionFrontiers(branches);
    return;
  }

  if (auto wait = dyn_cast<WaitOp>(op)) {
    // Join only the ranks whose tokens this wait lists. Rank S stays put
    // when the wait does not carry S's token, so S's pack is not completed
    // by a wait for R. The last op inside a task is not this event.
    llvm::SmallDenseSet<int64_t, 4> joined;
    for (Value token : wait.getTokens()) {
      Operation *def = token.getDefiningOp();
      if (!def)
        continue;
      graph.addEdge(def, op);
      std::optional<int64_t> rank;
      if (auto task = dyn_cast<TaskOp>(def))
        rank = taskRank(task);
      else
        rank = rankOf(def);
      if (!rank || !joined.insert(*rank).second)
        continue;
      graph.addEdges(front.lookup(*rank), op);
      front[*rank].assign({op});
    }
    return;
  }

  std::optional<int64_t> rank = rankOf(op);
  if (!rank) {
    if (isa<BarrierOp>(op)) {
      for (Value token : op->getOperands())
        if (Operation *def = token.getDefiningOp())
          graph.addEdge(def, op);
    }
    return;
  }
  graph.addEdges(front.lookup(*rank), op);
  if (isa<BarrierOp>(op)) {
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
