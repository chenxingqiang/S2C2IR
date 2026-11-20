//===- HBGraph.cpp - Shared happens-before graph ---------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/ExecutionModel/HBGraph.h"

#include "s2c2/Comm/CommOps.h"
#include "s2c2/Schedule/ScheduleOps.h"

#include "mlir/Dialect/SCF/IR/SCF.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"

#include <algorithm>

using namespace mlir;
using namespace mlir::s2c2;
using namespace mlir::s2c2::exec;
using comm::BarrierOp;
using sched::ConcurrentOp;
using sched::OverlapOp;
using sched::PipelineOp;
using sched::StageOp;
using sched::TaskOp;
using sched::WaitOp;

void HBGraph::addEdge(Operation *from, Operation *to) {
  if (!from || !to || from == to)
    return;
  auto &list = succ[from];
  if (!llvm::is_contained(list, to))
    list.push_back(to);
}

void HBGraph::addEdges(ArrayRef<Operation *> froms, Operation *to) {
  for (Operation *from : froms)
    addEdge(from, to);
}

bool HBGraph::reaches(Operation *from, Operation *to) const {
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

namespace {

void walkSeq(Block &block, ArrayRef<Operation *> incoming,
             SmallVectorImpl<Operation *> &outgoing, HBGraph &graph);

void walkOp(Operation *op, ArrayRef<Operation *> incoming,
            SmallVectorImpl<Operation *> &outgoing, HBGraph &graph) {
  if (auto task = dyn_cast<TaskOp>(op)) {
    if (task.getBody().empty()) {
      graph.addEdges(incoming, op);
      outgoing.assign({op});
      return;
    }
    SmallVector<Operation *> bodyOut;
    walkSeq(task.getBody().front(), incoming, bodyOut, graph);
    graph.addEdges(bodyOut, op);
    outgoing.assign(bodyOut.begin(), bodyOut.end());
    outgoing.push_back(op);
    return;
  }

  if (auto conc = dyn_cast<ConcurrentOp>(op)) {
    SmallVector<Operation *> join;
    if (!conc.getBody().empty()) {
      for (TaskOp task : conc.getBody().front().getOps<TaskOp>()) {
        SmallVector<Operation *> taskOut;
        walkOp(task, incoming, taskOut, graph);
        join.append(taskOut.begin(), taskOut.end());
      }
    }
    graph.addEdges(join, op);
    outgoing = std::move(join);
    outgoing.push_back(op);
    return;
  }

  if (auto pipe = dyn_cast<PipelineOp>(op)) {
    SmallVector<Operation *> cur(incoming.begin(), incoming.end());
    if (!pipe.getBody().empty()) {
      for (StageOp stage : pipe.getBody().front().getOps<StageOp>()) {
        if (stage.getBody().empty())
          continue;
        SmallVector<Operation *> stageOut;
        walkSeq(stage.getBody().front(), cur, stageOut, graph);
        graph.addEdges(stageOut, stage);
        cur = std::move(stageOut);
        cur.push_back(stage);
      }
    }
    graph.addEdges(cur, op);
    outgoing = std::move(cur);
    outgoing.push_back(op);
    return;
  }

  if (auto overlap = dyn_cast<OverlapOp>(op)) {
    SmallVector<Operation *> computeOut, commOut;
    if (!overlap.getCompute().empty())
      walkSeq(overlap.getCompute().front(), incoming, computeOut, graph);
    if (!overlap.getCommunicate().empty())
      walkSeq(overlap.getCommunicate().front(), incoming, commOut, graph);
    SmallVector<Operation *> join(computeOut.begin(), computeOut.end());
    join.append(commOut.begin(), commOut.end());
    graph.addEdges(join, op);
    outgoing = std::move(join);
    outgoing.push_back(op);
    return;
  }

  if (auto forOp = dyn_cast<scf::ForOp>(op)) {
    if (forOp.getBodyRegion().empty()) {
      graph.addEdges(incoming, op);
      outgoing.assign({op});
      return;
    }
    SmallVector<Operation *> bodyOut;
    walkSeq(*forOp.getBody(), incoming, bodyOut, graph);
    graph.addEdges(bodyOut, op);
    outgoing = std::move(bodyOut);
    outgoing.push_back(op);
    return;
  }

  if (auto ifOp = dyn_cast<scf::IfOp>(op)) {
    SmallVector<Operation *> join;
    if (Block *thenB = ifOp.thenBlock()) {
      SmallVector<Operation *> out;
      walkSeq(*thenB, incoming, out, graph);
      join.append(out.begin(), out.end());
    }
    if (Block *elseB = ifOp.elseBlock()) {
      SmallVector<Operation *> out;
      walkSeq(*elseB, incoming, out, graph);
      join.append(out.begin(), out.end());
    }
    graph.addEdges(join, op);
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
      walkSeq(region.front(), incoming, out, graph);
      join.append(out.begin(), out.end());
    }
    graph.addEdges(join, op);
    outgoing = std::move(join);
    outgoing.push_back(op);
    return;
  }

  graph.addEdges(incoming, op);
  if (isa<WaitOp, BarrierOp>(op)) {
    for (Value token : op->getOperands()) {
      if (Operation *def = token.getDefiningOp())
        graph.addEdge(def, op);
    }
  }
  outgoing.assign({op});
}

void walkSeq(Block &block, ArrayRef<Operation *> incoming,
             SmallVectorImpl<Operation *> &outgoing, HBGraph &graph) {
  SmallVector<Operation *> frontier(incoming.begin(), incoming.end());
  for (Operation &op : block.without_terminator()) {
    SmallVector<Operation *> next;
    walkOp(&op, frontier, next, graph);
    frontier = std::move(next);
  }
  if (Operation *term = block.getTerminator()) {
    graph.addEdges(frontier, term);
    outgoing.assign({term});
    return;
  }
  outgoing = std::move(frontier);
}

} // namespace

void mlir::s2c2::exec::buildProgramOrder(func::FuncOp func, HBGraph &graph) {
  if (func.getBody().empty())
    return;
  SmallVector<Operation *> unused;
  walkSeq(func.getBody().front(), {}, unused, graph);
}

void mlir::s2c2::exec::buildProgramOrder(ModuleOp module, HBGraph &graph) {
  for (func::FuncOp func : module.getOps<func::FuncOp>())
    buildProgramOrder(func, graph);
}

bool mlir::s2c2::exec::linearExtension(ArrayRef<Operation *> ops,
                                       const HBGraph &graph,
                                       SmallVectorImpl<Operation *> &order) {
  order.clear();
  if (ops.empty())
    return true;
  llvm::DenseMap<Operation *, int> index;
  for (auto [i, op] : llvm::enumerate(ops))
    index[op] = static_cast<int>(i);

  SmallVector<SmallVector<int>> succ(ops.size());
  SmallVector<int> indeg(ops.size(), 0);
  for (auto [i, op] : llvm::enumerate(ops)) {
    auto it = graph.successors().find(op);
    if (it == graph.successors().end())
      continue;
    for (Operation *next : it->second) {
      auto found = index.find(next);
      if (found == index.end() || found->second == static_cast<int>(i))
        continue;
      succ[i].push_back(found->second);
      ++indeg[found->second];
    }
  }

  SmallVector<int> ready;
  for (int i = 0, n = static_cast<int>(ops.size()); i < n; ++i)
    if (indeg[i] == 0)
      ready.push_back(i);

  while (!ready.empty()) {
    auto best = std::min_element(ready.begin(), ready.end());
    int chosen = *best;
    ready.erase(best);
    order.push_back(ops[chosen]);
    for (int dst : succ[chosen]) {
      if (--indeg[dst] == 0)
        ready.push_back(dst);
    }
  }
  return order.size() == ops.size();
}
