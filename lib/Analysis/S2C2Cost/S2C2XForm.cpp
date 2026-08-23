//===- S2C2XForm.cpp - Realization transformation T : P → P' ----*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// v0.5.0: T_id(P) = P. HB equality by construction.
// v0.5.1: T_reorder swaps one HB-independent concurrent sibling
// pair. HB(P') = HB(P) is an executable edge-set gate (same
// PO ∪ SW ∪ ConstructOrder walk as CheckS2C2Execution). Not a
// rewrite framework, not Search, not Concurrent → Pipeline.
//
//===----------------------------------------------------------------------===//

#include "s2c2/S2C2Family.h"
#include "s2c2/S2C2Legality.h"
#include "s2c2/S2C2Passes.h"

#include "s2c2/Comm/CommOps.h"
#include "s2c2/Schedule/ScheduleOps.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/raw_ostream.h"

#include <algorithm>
#include <utility>

namespace mlir::s2c2 {
#define GEN_PASS_DEF_S2C2XFORM
#include "s2c2/S2C2Passes.h.inc"

using comm::BarrierOp;
using sched::ConcurrentOp;
using sched::OverlapOp;
using sched::PipelineOp;
using sched::StageOp;
using sched::TaskOp;
using sched::WaitOp;

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

void walkHBOp(Operation *op, ArrayRef<Operation *> incoming,
              SmallVectorImpl<Operation *> &outgoing, HBGraph &g);
void walkHBSeq(Block &block, ArrayRef<Operation *> incoming,
               SmallVectorImpl<Operation *> &outgoing, HBGraph &g);

void walkHBSeq(Block &block, ArrayRef<Operation *> incoming,
               SmallVectorImpl<Operation *> &outgoing, HBGraph &g) {
  SmallVector<Operation *> frontier(incoming.begin(), incoming.end());
  for (Operation &op : block.without_terminator()) {
    SmallVector<Operation *> next;
    walkHBOp(&op, frontier, next, g);
    frontier = std::move(next);
  }
  if (Operation *term = block.getTerminator()) {
    g.addEdges(frontier, term);
    outgoing.assign({term});
    return;
  }
  outgoing = std::move(frontier);
}

void walkHBOp(Operation *op, ArrayRef<Operation *> incoming,
              SmallVectorImpl<Operation *> &outgoing, HBGraph &g) {
  if (auto task = dyn_cast<TaskOp>(op)) {
    SmallVector<Operation *> bodyOut;
    walkHBSeq(task.getBody().front(), incoming, bodyOut, g);
    g.addEdges(bodyOut, op);
    outgoing.assign(bodyOut.begin(), bodyOut.end());
    outgoing.push_back(op);
    return;
  }
  if (auto conc = dyn_cast<ConcurrentOp>(op)) {
    SmallVector<Operation *> join;
    for (TaskOp task : conc.getBody().front().getOps<TaskOp>()) {
      SmallVector<Operation *> taskOut;
      walkHBOp(task, incoming, taskOut, g);
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
      walkHBSeq(stage.getBody().front(), cur, stageOut, g);
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
    walkHBSeq(overlap.getCompute().front(), incoming, computeOut, g);
    walkHBSeq(overlap.getCommunicate().front(), incoming, commOut, g);
    SmallVector<Operation *> join(computeOut.begin(), computeOut.end());
    join.append(commOut.begin(), commOut.end());
    g.addEdges(join, op);
    outgoing = std::move(join);
    outgoing.push_back(op);
    return;
  }
  g.addEdges(incoming, op);
  if (isa<WaitOp, BarrierOp>(op)) {
    for (Value token : op->getOperands())
      if (Operation *def = token.getDefiningOp())
        g.addEdge(def, op);
  }
  outgoing.assign({op});
}

void buildHB(func::FuncOp func, HBGraph &g) {
  g = HBGraph();
  if (func.getBody().empty())
    return;
  SmallVector<Operation *> unused;
  walkHBSeq(func.getBody().front(), {}, unused, g);
}

using HBEdge = std::pair<Operation *, Operation *>;

SmallVector<HBEdge> edgeSet(const HBGraph &g) {
  SmallVector<HBEdge> edges;
  for (const auto &kv : g.succ)
    for (Operation *to : kv.second)
      edges.emplace_back(kv.first, to);
  llvm::sort(edges);
  return edges;
}

bool hbEqual(const HBGraph &a, const HBGraph &b) {
  return edgeSet(a) == edgeSet(b);
}

bool usesDefFrom(Operation *userRoot, Operation *defRoot) {
  bool hit = false;
  userRoot->walk([&](Operation *op) {
    for (Value v : op->getOperands()) {
      Operation *def = v.getDefiningOp();
      if (def && (def == defRoot || defRoot->isAncestor(def)))
        hit = true;
    }
  });
  return hit;
}

bool subtreeReaches(const HBGraph &g, Operation *fromRoot,
                    Operation *toRoot) {
  bool hit = false;
  fromRoot->walk([&](Operation *from) {
    toRoot->walk([&](Operation *to) {
      if (g.reaches(from, to))
        hit = true;
    });
  });
  return hit;
}

bool findIndependentAdjacent(func::FuncOp func, const HBGraph &g, TaskOp &left,
                             TaskOp &right) {
  bool found = false;
  func.walk([&](ConcurrentOp conc) {
    if (found)
      return;
    SmallVector<TaskOp> tasks;
    for (TaskOp t : conc.getBody().front().getOps<TaskOp>())
      tasks.push_back(t);
    for (size_t i = 0; i + 1 < tasks.size(); ++i) {
      TaskOp a = tasks[i];
      TaskOp b = tasks[i + 1];
      if (usesDefFrom(b, a) || usesDefFrom(a, b))
        continue;
      if (subtreeReaches(g, a, b) || subtreeReaches(g, b, a))
        continue;
      left = a;
      right = b;
      found = true;
      return;
    }
  });
  return found;
}

int countEnumF(func::FuncOp func, ArrayRef<StringRef> schedF,
               ArrayRef<StringRef> mapF, ArrayRef<StringRef> devF) {
  int rebuilt = 0;
  for (StringRef s : schedF)
    for (StringRef m : mapF)
      for (StringRef d : devF)
        if (isLegalRealization(func, s, m, d))
          ++rebuilt;
  return rebuilt;
}

struct S2C2XForm : impl::S2C2XFormBase<S2C2XForm> {
  using impl::S2C2XFormBase<S2C2XForm>::S2C2XFormBase;

  void runOnOperation() override {
    Operation *mod = getOperation();
    if (kind != "id" && kind != "concurrent-reorder") {
      mod->emitError() << "s2c2-xform: kind must be id or concurrent-reorder";
      signalPassFailure();
      return;
    }

    SmallVector<StringRef, 4> schedF, mapF, devF;
    if (failed(selectFamilyAxis(scheds, "xform", "sched", familyF0Scheds(),
                                schedF, mod)) ||
        failed(selectFamilyAxis(maps, "xform", "map", familyF0Maps(), mapF,
                                mod)) ||
        failed(selectFamilyAxis(devices, "xform", "device", familyF0Devices(),
                                devF, mod))) {
      signalPassFailure();
      return;
    }

    for (auto func : getOperation().getOps<func::FuncOp>()) {
      if (func.getBody().empty())
        continue;
      if (kind == "id") {
        // T_id: P' = P. HB equality is construction, not a new HB engine.
        int rebuilt = countEnumF(func, schedF, mapF, devF);
        llvm::errs() << "s2c2-xform func=" << func.getName() << " kind=id\n";
        llvm::errs() << "s2c2-xform func=" << func.getName() << " hb-eq=1\n";
        llvm::errs() << "s2c2-xform func=" << func.getName()
                     << " x-rebuilt count=" << rebuilt << "\n";
        continue;
      }

      HBGraph before;
      buildHB(func, before);
      TaskOp left, right;
      llvm::errs() << "s2c2-xform func=" << func.getName()
                   << " kind=concurrent-reorder\n";
      if (!findIndependentAdjacent(func, before, left, right)) {
        llvm::errs() << "s2c2-xform func=" << func.getName()
                     << " accepted=0\n";
        continue;
      }

      right->moveBefore(left);
      HBGraph after;
      buildHB(func, after);
      if (!hbEqual(before, after)) {
        left->moveBefore(right);
        llvm::errs() << "s2c2-xform func=" << func.getName()
                     << " accepted=0\n";
        continue;
      }

      int rebuilt = countEnumF(func, schedF, mapF, devF);
      llvm::errs() << "s2c2-xform func=" << func.getName() << " accepted=1\n";
      llvm::errs() << "s2c2-xform func=" << func.getName() << " hb-eq=1\n";
      llvm::errs() << "s2c2-xform func=" << func.getName()
                   << " x-rebuilt count=" << rebuilt << "\n";
    }
  }
};
} // namespace
} // namespace mlir::s2c2
