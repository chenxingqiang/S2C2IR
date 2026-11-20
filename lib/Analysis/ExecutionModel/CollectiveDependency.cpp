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

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/Support/raw_ostream.h"

#include <limits>
#include <string>
#include <tuple>
#include <utility>

using namespace mlir;
using namespace mlir::s2c2;
using namespace mlir::s2c2::exec;
using sched::ConcurrentOp;
using sched::TaskOp;
using sched::YieldOp;
using stor::LocalizeOp;
using stor::PackOp;
using stor::UnpackOp;
using stor::getLogicalObject;

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

int64_t meshSizeOf(shard::GridOp grid) {
  if (!grid || grid.getShape().empty())
    return 0;
  int64_t n = 1;
  for (int64_t extent : grid.getShape()) {
    if (extent <= 0 || ShapedType::isDynamic(extent))
      return 0;
    if (n > std::numeric_limits<int64_t>::max() / extent)
      return 0;
    n *= extent;
  }
  return n;
}

Value globalObject(Value buffer) {
  Value obj = getLogicalObject(buffer);
  if (!obj)
    return {};
  if (auto localize = obj.getDefiningOp<LocalizeOp>())
    return localize.getGlobal();
  return obj;
}

std::string signatureOf(Operation *op) {
  std::string out;
  llvm::raw_string_ostream os(out);
  os << op->getName().getStringRef() << '|';
  if (auto allReduce = dyn_cast<shard::AllReduceOp>(op)) {
    os << allReduce.getGrid() << '|';
    for (int16_t axis : allReduce.getGridAxes())
      os << axis << ',';
    os << '|' << shard::stringifyReductionKind(allReduce.getReduction());
  } else if (auto gather = dyn_cast<shard::AllGatherOp>(op)) {
    os << gather.getGrid() << '|';
    for (int16_t axis : gather.getGridAxes())
      os << axis << ',';
    os << "|gather=" << gather.getGatherAxis();
  } else if (auto scatter = dyn_cast<shard::ReduceScatterOp>(op)) {
    os << scatter.getGrid() << '|';
    for (int16_t axis : scatter.getGridAxes())
      os << axis << ',';
    os << "|scatter=" << scatter.getScatterAxis();
    os << '|' << shard::stringifyReductionKind(scatter.getReduction());
  }
  os << '|';
  if (op->getNumOperands())
    op->getOperand(0).getType().print(os);
  os << "->";
  if (op->getNumResults())
    op->getResult(0).getType().print(os);
  return out;
}

struct Slot {
  Operation *collective = nullptr;
  Operation *input = nullptr;
  int64_t rank = -1;
  Value inputObject;
  Value resultObject;
  std::string signature;
  SmallVector<Operation *, 2> resultPacks;
};

using Key = std::tuple<std::string, const void *, const void *>;

Key keyOf(const Slot &slot) {
  return Key{slot.signature, slot.inputObject.getAsOpaquePointer(),
             slot.resultObject.getAsOpaquePointer()};
}

} // namespace

CollectiveMatch
mlir::s2c2::exec::matchCollectiveInstances(func::FuncOp func) {
  CollectiveMatch match;
  SmallVector<StringRef> meshOrder;
  llvm::DenseMap<StringRef, llvm::DenseMap<int64_t, SmallVector<Slot>>> grouped;
  llvm::DenseMap<StringRef, shard::GridOp> grids;
  llvm::DenseMap<StringRef, Operation *> firstOp;
  func.walk([&](Operation *op) {
    if (!isV0Collective(op))
      return;
    auto unpack = op->getOperand(0).getDefiningOp<UnpackOp>();
    if (!unpack)
      return;
    auto rank = ownerRank(unpack.getBuffer());
    if (!rank)
      return;
    shard::GridOp grid = gridOf(op);
    StringRef mesh = grid ? grid.getSymName() : "";
    if (!grouped.contains(mesh)) {
      meshOrder.push_back(mesh);
      firstOp[mesh] = op;
    }
    Slot slot;
    slot.collective = op;
    slot.input = unpack;
    slot.rank = *rank;
    slot.inputObject = globalObject(unpack.getBuffer());
    slot.signature = signatureOf(op);
    func.walk([&](PackOp pack) {
      if (!isCollectiveImage(pack.getValue(), op))
        return;
      auto owner = ownerRank(pack.getBuffer());
      if (!owner || *owner != *rank)
        return;
      slot.resultPacks.push_back(pack);
      Value object = globalObject(pack.getBuffer());
      if (!slot.resultObject)
        slot.resultObject = object;
      else if (slot.resultObject != object && !match.faultOp) {
        match.faultOp = op;
        match.message = "collective instance result identity does not match";
      }
    });
    grouped[mesh][*rank].push_back(std::move(slot));
    grids[mesh] = grid;
  });
  if (match.faultOp)
    return match;

  for (StringRef mesh : meshOrder) {
    auto &byRank = grouped[mesh];
    int64_t meshSize = meshSizeOf(grids.lookup(mesh));
    Operation *anchor = firstOp.lookup(mesh);
    if (meshSize <= 0) {
      match.faultOp = anchor;
      match.message = "rank is outside the mesh";
      return match;
    }
    for (auto &ranks : byRank) {
      if (ranks.first < 0 || ranks.first >= meshSize) {
        match.faultOp = ranks.second.front().collective;
        match.message = "rank is outside the mesh";
        return match;
      }
    }
    size_t count = byRank.lookup(0).size();
    bool uneven = false;
    for (int64_t rank = 0; rank < meshSize; ++rank) {
      if (byRank.lookup(rank).size() != count)
        uneven = true;
    }
    if (uneven) {
      match.faultOp = anchor;
      match.message = "collective instance is missing a rank";
      return match;
    }
    if (count == 0)
      continue;

    SmallVector<SmallVector<Key>> sequences;
    for (int64_t rank = 0; rank < meshSize; ++rank) {
      SmallVector<Key> keys;
      for (Slot &slot : byRank[rank])
        keys.push_back(keyOf(slot));
      sequences.push_back(std::move(keys));
    }
    bool sameOrder = true;
    for (size_t rank = 1; rank < sequences.size(); ++rank)
      if (sequences[rank] != sequences.front())
        sameOrder = false;
    if (!sameOrder) {
      SmallVector<SmallVector<Key>> sorted = sequences;
      for (auto &keys : sorted)
        llvm::sort(keys);
      bool sameMultiset = true;
      for (size_t rank = 1; rank < sorted.size(); ++rank)
        if (sorted[rank] != sorted.front())
          sameMultiset = false;
      match.faultOp = anchor;
      if (sameMultiset) {
        match.message = "collective instance call order does not match";
        return match;
      }
      bool mixedObject = false;
      bool mixedResult = false;
      bool mixedSignature = false;
      for (size_t index = 0; index < count; ++index) {
        const Slot &base = byRank[0][index];
        for (int64_t rank = 1; rank < meshSize; ++rank) {
          const Slot &other = byRank[rank][index];
          if (other.signature != base.signature)
            mixedSignature = true;
          else if (other.inputObject != base.inputObject)
            mixedObject = true;
          else if (other.resultObject != base.resultObject)
            mixedResult = true;
        }
      }
      if (mixedObject)
        match.message = "collective instance mixes logical objects";
      else if (mixedResult && !mixedSignature)
        match.message = "collective instance result identity does not match";
      else
        match.message = "collective instance call order does not match";
      return match;
    }

    for (size_t index = 0; index < count; ++index) {
      CollectiveInstance instance;
      instance.mesh = mesh;
      instance.callsite = static_cast<unsigned>(index);
      instance.kind = byRank[0][index].collective->getName().getStringRef();
      for (int64_t rank = 0; rank < meshSize; ++rank) {
        Slot &slot = byRank[rank][index];
        CollectiveParticipant participant;
        participant.collective = slot.collective;
        participant.input = slot.input;
        participant.rank = slot.rank;
        participant.inputObject = slot.inputObject;
        participant.resultObject = slot.resultObject;
        participant.resultPacks = slot.resultPacks;
        instance.participants.push_back(std::move(participant));
      }
      match.instances.push_back(std::move(instance));
    }
  }
  return match;
}

void mlir::s2c2::exec::addCollectiveDependencies(func::FuncOp func,
                                                HBGraph &graph) {
  CollectiveMatch match = matchCollectiveInstances(func);
  if (match.faultOp)
    return;
  for (CollectiveInstance &instance : match.instances) {
    for (CollectiveParticipant &self : instance.participants) {
      graph.addEdge(self.input, self.collective);
      for (Operation *out : self.resultPacks)
        graph.addEdge(self.collective, out);
      for (CollectiveParticipant &other : instance.participants) {
        if (other.rank == self.rank)
          continue;
        graph.addEdge(other.input, self.collective);
        for (Operation *out : self.resultPacks)
          graph.addEdge(other.collective, out);
      }
    }
  }
}

void mlir::s2c2::exec::buildHbD(func::FuncOp func, HBGraph &graph) {
  buildRankOrder(func, graph);
  addCollectiveDependencies(func, graph);
}
