//===- CheckS2C2Execution.cpp - HB / validity oracle ------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// MustProve checker for Execution Semantics E1–E8. Not token lowering.
// Concurrent sibling lexical order is not happens-before.
// Validity of a stor.transfer result follows SSA through task /
// concurrent yields onto the parent result (storage pipeline consume).
// Phase 3I also walks `scf.for` / `scf.if` / `scf.index_switch` as
// sequential regions and aliases yields onto their results (not a
// new HB).
//
//===----------------------------------------------------------------------===//

#include "s2c2/Comm/CommOps.h"
#include "s2c2/S2C2Passes.h"
#include "s2c2/Schedule/ScheduleOps.h"
#include "s2c2/Storage/StorageOps.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/SmallVector.h"

namespace mlir::s2c2 {
#define GEN_PASS_DEF_CHECKS2C2EXECUTION
#include "s2c2/S2C2Passes.h.inc"

using comm::BarrierOp;
using comm::CopyOp;
using comm::StreamOp;
using sched::ConcurrentOp;
using sched::OverlapOp;
using sched::PipelineOp;
using sched::StageOp;
using sched::TaskOp;
using sched::WaitOp;
using sched::YieldOp;
using stor::PackOp;
using stor::TransferOp;
using stor::UnpackOp;

namespace {
struct HBGraph {
  llvm::DenseMap<Operation *, SmallVector<Operation *, 2>> succ;

  void addEdge(Operation *from, Operation *to) {
    if (!from || !to || from == to)
      return;
    auto &list = succ[from];
    if (!llvm::is_contained(list, to))
      list.push_back(to);
  }

  void addEdges(ArrayRef<Operation *> froms, Operation *to) {
    for (Operation *from : froms)
      addEdge(from, to);
  }

  bool reaches(Operation *from, Operation *to) const {
    if (!from || !to || from == to)
      return false;
    SmallPtrSet<Operation *, 16> seen;
    SmallVector<Operation *, 16> stack({from});
    while (!stack.empty()) {
      Operation *cur = stack.pop_back_val();
      auto it = succ.find(cur);
      if (it == succ.end())
        continue;
      for (Operation *next : it->second) {
        if (next == to)
          return true;
        if (seen.insert(next).second)
          stack.push_back(next);
      }
    }
    return false;
  }
};

struct CheckS2C2Execution : impl::CheckS2C2ExecutionBase<CheckS2C2Execution> {
  using impl::CheckS2C2ExecutionBase<CheckS2C2Execution>::CheckS2C2ExecutionBase;

  void walkOp(Operation *op, ArrayRef<Operation *> incoming,
              SmallVectorImpl<Operation *> &outgoing, HBGraph &g);
  void walkSeq(Block &block, ArrayRef<Operation *> incoming,
               SmallVectorImpl<Operation *> &outgoing, HBGraph &g);

  void runOnOperation() override;
};

void CheckS2C2Execution::walkSeq(Block &block, ArrayRef<Operation *> incoming,
                                 SmallVectorImpl<Operation *> &outgoing,
                                 HBGraph &g) {
  SmallVector<Operation *> frontier(incoming.begin(), incoming.end());
  for (Operation &op : block.without_terminator()) {
    SmallVector<Operation *> next;
    walkOp(&op, frontier, next, g);
    frontier = std::move(next);
  }
  if (Operation *term = block.getTerminator()) {
    g.addEdges(frontier, term);
    outgoing.assign({term});
    return;
  }
  outgoing = std::move(frontier);
}

void CheckS2C2Execution::walkOp(Operation *op, ArrayRef<Operation *> incoming,
                                SmallVectorImpl<Operation *> &outgoing,
                                HBGraph &g) {
  if (auto task = dyn_cast<TaskOp>(op)) {
    SmallVector<Operation *> bodyOut;
    walkSeq(task.getBody().front(), incoming, bodyOut, g);
    g.addEdges(bodyOut, op);
    outgoing.assign(bodyOut.begin(), bodyOut.end());
    outgoing.push_back(op);
    return;
  }

  if (auto conc = dyn_cast<ConcurrentOp>(op)) {
    // NoOrderingRequirement: same incoming frontier, no sibling PO.
    SmallVector<Operation *> join;
    for (TaskOp task : conc.getBody().front().getOps<TaskOp>()) {
      SmallVector<Operation *> taskOut;
      walkOp(task, incoming, taskOut, g);
      join.append(taskOut.begin(), taskOut.end());
    }
    g.addEdges(join, op);
    outgoing = std::move(join);
    outgoing.push_back(op);
    return;
  }

  if (auto pipe = dyn_cast<PipelineOp>(op)) {
    SmallVector<Operation *> cur(incoming.begin(), incoming.end());
    for (StageOp stage : pipe.getBody().front().getOps<StageOp>()) {
      SmallVector<Operation *> stageOut;
      walkSeq(stage.getBody().front(), cur, stageOut, g);
      g.addEdges(stageOut, stage);
      cur = std::move(stageOut);
      cur.push_back(stage);
    }
    g.addEdges(cur, op);
    outgoing = std::move(cur);
    outgoing.push_back(op);
    return;
  }

  if (auto overlap = dyn_cast<OverlapOp>(op)) {
    SmallVector<Operation *> computeOut, commOut;
    walkSeq(overlap.getCompute().front(), incoming, computeOut, g);
    walkSeq(overlap.getCommunicate().front(), incoming, commOut, g);
    SmallVector<Operation *> join(computeOut.begin(), computeOut.end());
    join.append(commOut.begin(), commOut.end());
    g.addEdges(join, op);
    outgoing = std::move(join);
    outgoing.push_back(op);
    return;
  }

  if (auto forOp = dyn_cast<scf::ForOp>(op)) {
    if (forOp.getBodyRegion().empty()) {
      g.addEdges(incoming, op);
      outgoing.assign({op});
      return;
    }
    SmallVector<Operation *> bodyOut;
    walkSeq(*forOp.getBody(), incoming, bodyOut, g);
    g.addEdges(bodyOut, op);
    outgoing = std::move(bodyOut);
    outgoing.push_back(op);
    return;
  }

  if (auto ifOp = dyn_cast<scf::IfOp>(op)) {
    SmallVector<Operation *> join;
    if (Block *thenB = ifOp.thenBlock()) {
      SmallVector<Operation *> out;
      walkSeq(*thenB, incoming, out, g);
      join.append(out.begin(), out.end());
    }
    if (Block *elseB = ifOp.elseBlock()) {
      SmallVector<Operation *> out;
      walkSeq(*elseB, incoming, out, g);
      join.append(out.begin(), out.end());
    }
    g.addEdges(join, op);
    outgoing = std::move(join);
    outgoing.push_back(op);
    return;
  }

  if (auto sw = dyn_cast<scf::IndexSwitchOp>(op)) {
    SmallVector<Operation *> join;
    for (Region &region : sw->getRegions()) {
      if (region.empty())
        continue;
      SmallVector<Operation *> out;
      walkSeq(region.front(), incoming, out, g);
      join.append(out.begin(), out.end());
    }
    g.addEdges(join, op);
    outgoing = std::move(join);
    outgoing.push_back(op);
    return;
  }

  g.addEdges(incoming, op);
  if (isa<WaitOp, BarrierOp>(op)) {
    for (Value token : op->getOperands()) {
      if (Operation *def = token.getDefiningOp())
        g.addEdge(def, op);
    }
  }
  outgoing.assign({op});
}

static bool consumesToken(Operation *op, Value token) {
  return isa<WaitOp, BarrierOp>(op) && llvm::is_contained(op->getOperands(), token);
}

static bool eventVisible(Value token, Operation *read, const HBGraph &g) {
  for (OpOperand &use : token.getUses()) {
    Operation *user = use.getOwner();
    if (consumesToken(user, token) && g.reaches(user, read))
      return true;
  }
  return false;
}

void CheckS2C2Execution::runOnOperation() {
  HBGraph g;
  for (auto func : getOperation().getOps<func::FuncOp>()) {
    if (func.getBody().empty())
      continue;
    SmallVector<Operation *> unused;
    walkSeq(func.getBody().front(), {}, unused, g);
  }

  SmallVector<std::pair<Operation *, Value>> reads;
  llvm::DenseMap<Value, SmallVector<Operation *>> syncWrites;
  SmallVector<std::pair<Value, Value>> eventWrites;

  getOperation()->walk([&](Operation *op) {
    if (auto pack = dyn_cast<PackOp>(op))
      syncWrites[pack.getBuffer()].push_back(op);
    else if (auto xfer = dyn_cast<TransferOp>(op)) {
      syncWrites[xfer.getBuffer()].push_back(op);
      reads.push_back({op, xfer.getSource()});
    } else if (auto copy = dyn_cast<CopyOp>(op)) {
      reads.push_back({op, copy.getSrc()});
      if (copy.getNumResults() == 0)
        syncWrites[copy.getDst()].push_back(op);
      else {
        eventWrites.push_back({copy.getToken(), copy.getDst()});
        if (auto task = op->getParentOfType<TaskOp>())
          eventWrites.push_back({task.getToken(), copy.getDst()});
      }
    } else if (auto stream = dyn_cast<StreamOp>(op)) {
      reads.push_back({op, stream.getSrc()});
      eventWrites.push_back({stream.getToken(), stream.getDst()});
      if (auto task = op->getParentOfType<TaskOp>())
        eventWrites.push_back({task.getToken(), stream.getDst()});
    } else if (auto unpack = dyn_cast<UnpackOp>(op)) {
      reads.push_back({op, unpack.getBuffer()});
    }
  });

  // Validity follows SSA through task / concurrent yields. The inner
  // transfer writes a region result; the parent SSA is a different
  // Value but the same residency after the concurrent join.
  bool aliased = true;
  while (aliased) {
    aliased = false;
    getOperation()->walk([&](Operation *op) {
      auto copyWrites = [&](Value from, Value to) {
        if (from == to)
          return;
        for (Operation *write : syncWrites.lookup(from)) {
          auto &dst = syncWrites[to];
          if (!llvm::is_contained(dst, write)) {
            dst.push_back(write);
            aliased = true;
          }
        }
      };
      if (auto task = dyn_cast<TaskOp>(op)) {
        if (task.getBody().empty())
          return;
        auto yield = dyn_cast<YieldOp>(task.getBody().front().getTerminator());
        if (!yield)
          return;
        for (auto [from, to] :
             llvm::zip(yield.getOperands(), task.getValues()))
          copyWrites(from, to);
      } else if (auto conc = dyn_cast<ConcurrentOp>(op)) {
        if (conc.getBody().empty())
          return;
        auto yield = dyn_cast<YieldOp>(conc.getBody().front().getTerminator());
        if (!yield)
          return;
        for (auto [from, to] :
             llvm::zip(yield.getOperands(), conc.getResults()))
          copyWrites(from, to);
      } else if (auto ifOp = dyn_cast<scf::IfOp>(op)) {
        for (Region &region : ifOp->getRegions()) {
          if (region.empty())
            continue;
          auto yield = dyn_cast<scf::YieldOp>(region.front().getTerminator());
          if (!yield)
            continue;
          for (auto [from, to] :
               llvm::zip(yield.getOperands(), ifOp.getResults()))
            copyWrites(from, to);
        }
      } else if (auto sw = dyn_cast<scf::IndexSwitchOp>(op)) {
        for (Region &region : sw->getRegions()) {
          if (region.empty())
            continue;
          auto yield = dyn_cast<scf::YieldOp>(region.front().getTerminator());
          if (!yield)
            continue;
          for (auto [from, to] :
               llvm::zip(yield.getOperands(), sw.getResults()))
            copyWrites(from, to);
        }
      } else if (auto forOp = dyn_cast<scf::ForOp>(op)) {
        if (forOp.getBodyRegion().empty())
          return;
        auto yield = dyn_cast<scf::YieldOp>(forOp.getBody()->getTerminator());
        if (!yield)
          return;
        for (auto [from, to] :
             llvm::zip(yield.getOperands(), forOp.getResults()))
          copyWrites(from, to);
        for (auto [from, to] :
             llvm::zip(yield.getOperands(), forOp.getRegionIterArgs()))
          copyWrites(from, to);
        for (auto [from, to] :
             llvm::zip(forOp.getInitArgs(), forOp.getRegionIterArgs()))
          copyWrites(from, to);
      }
    });
  }

  bool failed = false;
  for (auto [readOp, residency] : reads) {
    bool defined = false;
    for (Operation *write : syncWrites.lookup(residency)) {
      if (g.reaches(write, readOp)) {
        defined = true;
        break;
      }
    }
    if (!defined) {
      for (auto [token, dest] : eventWrites) {
        if (dest == residency && eventVisible(token, readOp, g)) {
          defined = true;
          break;
        }
      }
    }
    if (!defined) {
      readOp->emitOpError("read of residency is undefined: no happens-before "
                          "from a validity-establishing write");
      failed = true;
    }
  }

  if (failed)
    signalPassFailure();
}
} // namespace
} // namespace mlir::s2c2
