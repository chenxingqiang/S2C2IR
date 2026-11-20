//===- CollectiveDependency.cpp - SPMD collective edges ---------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/ExecutionModel/CollectiveDependency.h"
#include "s2c2/ExecutionModel/RankContext.h"

#include "s2c2/Schedule/ScheduleOps.h"
#include "s2c2/Storage/StorageOps.h"

#include "mlir/Dialect/Shard/IR/ShardOps.h"
#include "mlir/IR/SymbolTable.h"

using namespace mlir;
using namespace mlir::s2c2;
using namespace mlir::s2c2::exec;
using sched::ConcurrentOp;
using sched::TaskOp;
using sched::YieldOp;
using stor::PackOp;
using stor::UnpackOp;

bool mlir::s2c2::exec::isV0Collective(Operation *op) {
  StringRef name = op->getName().getStringRef();
  return name == "shard.all_reduce" || name == "shard.all_gather" ||
         name == "shard.reduce_scatter";
}

bool mlir::s2c2::exec::isCollectiveImage(Value value, Operation *collective) {
  if (!collective)
    return false;
  if (value == collective->getResult(0))
    return true;
  Operation *def = value.getDefiningOp();
  auto throughYield = [&](ValueRange yielded, ValueRange results) {
    for (auto [inner, outer] : llvm::zip(yielded, results)) {
      if (outer == value && isCollectiveImage(inner, collective))
        return true;
    }
    return false;
  };
  if (auto task = dyn_cast_or_null<TaskOp>(def)) {
    if (task.getBody().empty())
      return false;
    auto yield = dyn_cast<YieldOp>(task.getBody().front().getTerminator());
    return yield && throughYield(yield.getOperands(), task.getValues());
  }
  if (auto conc = dyn_cast_or_null<ConcurrentOp>(def)) {
    if (conc.getBody().empty())
      return false;
    auto yield = dyn_cast<YieldOp>(conc.getBody().front().getTerminator());
    return yield && throughYield(yield.getOperands(), conc.getResults());
  }
  return false;
}

namespace {

shard::GridOp gridOf(Operation *op) {
  auto sym = op->getAttrOfType<FlatSymbolRefAttr>("grid");
  if (!sym)
    return {};
  return dyn_cast_or_null<shard::GridOp>(
      SymbolTable::lookupNearestSymbolFrom(op, sym));
}

} // namespace

void mlir::s2c2::exec::addCollectiveDependencies(func::FuncOp func,
                                                HBGraph &graph) {
  struct Inst {
    Operation *collective = nullptr;
    Operation *input = nullptr;
    int64_t rank = 0;
    SmallVector<Operation *> resultPacks;
  };
  llvm::DenseMap<StringRef, llvm::DenseMap<StringRef, SmallVector<Inst>>>
      grouped;
  SmallVector<Operation *> collectives;
  func.walk([&](Operation *op) {
    if (isV0Collective(op))
      collectives.push_back(op);
  });
  for (Operation *op : collectives) {
    auto unpack = op->getOperand(0).getDefiningOp<UnpackOp>();
    if (!unpack)
      continue;
    auto rank = ownerRank(unpack.getBuffer());
    if (!rank)
      continue;
    Inst inst;
    inst.collective = op;
    inst.input = unpack;
    inst.rank = *rank;
    func.walk([&](PackOp pack) {
      if (!isCollectiveImage(pack.getValue(), op))
        return;
      auto owner = ownerRank(pack.getBuffer());
      if (owner && *owner == *rank)
        inst.resultPacks.push_back(pack);
    });
    shard::GridOp grid = gridOf(op);
    StringRef gridName = grid ? grid.getSymName() : "";
    grouped[gridName][op->getName().getStringRef()].push_back(std::move(inst));
  }
  for (auto &byName : grouped) {
    for (auto &entry : byName.second) {
      SmallVector<Inst> &insts = entry.second;
      for (Inst &self : insts) {
        graph.addEdge(self.input, self.collective);
        for (Operation *out : self.resultPacks)
          graph.addEdge(self.collective, out);
        for (Inst &other : insts) {
          if (other.rank == self.rank)
            continue;
          graph.addEdge(other.input, self.collective);
          for (Operation *out : self.resultPacks)
            graph.addEdge(other.collective, out);
        }
      }
    }
  }
}

void mlir::s2c2::exec::buildHbD(func::FuncOp func, HBGraph &graph) {
  buildRankOrder(func, graph);
  addCollectiveDependencies(func, graph);
}
