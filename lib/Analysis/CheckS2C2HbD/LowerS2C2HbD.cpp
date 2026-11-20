//===- LowerS2C2HbD.cpp - HB_D lowering fidelity ----------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// --lower-s2c2-hb-d=async keeps HB_D^source inside HB_D^target. Each
// multi-rank collective stays a participant, wrapped in sched.task when it
// is not already in one. MeshSize 1 is unchanged.
// --lower-s2c2-hb-d=sync recursively inlines nested sched.concurrent and
// sched.task. The resulting block is a linear extension of HB_D.
// Fidelity checks the recorded inclusion, input contribution, and output
// validity. No device library and no runtime.

#include "s2c2/ExecutionModel/CollectiveDependency.h"
#include "s2c2/ExecutionModel/EventDependency.h"
#include "s2c2/ExecutionModel/HBGraph.h"
#include "s2c2/ExecutionModel/RankContext.h"
#include "s2c2/S2C2Passes.h"
#include "s2c2/Schedule/ScheduleOps.h"
#include "s2c2/Storage/StorageOps.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Shard/IR/ShardOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"

#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"

#include <limits>
#include <optional>

namespace mlir::s2c2 {
#define GEN_PASS_DEF_LOWERS2C2HBD
#define GEN_PASS_DEF_CHECKS2C2HBDFIDELITY
#include "s2c2/S2C2Passes.h.inc"

using sched::ConcurrentOp;
using sched::TaskOp;
using sched::TokenType;
using sched::WaitOp;
using sched::YieldOp;
using stor::LocalizeOp;
using stor::PackOp;
using stor::UnpackOp;

namespace {
constexpr llvm::StringLiteral kAnchor("s2c2.hb_anchor");
constexpr llvm::StringLiteral kEdges("s2c2.hb_d_edges");
constexpr llvm::StringLiteral kLocalizes("s2c2.hb_d_localizes");
constexpr llvm::StringLiteral kCollectives("s2c2.hb_d_collectives");

static std::optional<int64_t> meshSizeOf(shard::GridOp grid) {
  if (!grid)
    return std::nullopt;
  int64_t n = 1;
  for (int64_t extent : grid.getShape()) {
    if (extent <= 0 || ShapedType::isDynamic(extent))
      return std::nullopt;
    if (n > std::numeric_limits<int64_t>::max() / extent)
      return std::nullopt;
    n *= extent;
  }
  if (grid.getShape().empty())
    return std::nullopt;
  return n;
}

static shard::GridOp gridOf(Operation *op) {
  auto sym = op->getAttrOfType<FlatSymbolRefAttr>("grid");
  if (!sym)
    return {};
  return dyn_cast_or_null<shard::GridOp>(
      SymbolTable::lookupNearestSymbolFrom(op, sym));
}

static bool hasCollective(func::FuncOp func) {
  bool found = false;
  func.walk([&](Operation *op) {
    if (exec::isV0Collective(op))
      found = true;
  });
  return found;
}

struct SourceRelation {
  SmallVector<int64_t> edges;
  SmallVector<int64_t> localizes;
  SmallVector<int64_t> collectives;
};

static int64_t anchorId(Operation *op) {
  auto attr = op->getAttrOfType<IntegerAttr>(kAnchor);
  if (!attr)
    return -1;
  return attr.getInt();
}

static void assignAnchors(func::FuncOp func, SourceRelation &rel) {
  int64_t next = 1;
  func.walk([&](Operation *op) {
    if (isa<func::FuncOp>(op))
      return;
    op->setAttr(kAnchor, IntegerAttr::get(IntegerType::get(op->getContext(), 64),
                                          next));
    if (isa<LocalizeOp>(op))
      rel.localizes.push_back(next);
    if (exec::isV0Collective(op))
      rel.collectives.push_back(next);
    ++next;
  });
}

static void recordEdges(func::FuncOp func, const exec::HBGraph &graph,
                        SourceRelation &rel) {
  SmallVector<Operation *> anchors;
  func.walk([&](Operation *op) {
    if (anchorId(op) > 0)
      anchors.push_back(op);
  });
  auto scheduleWrapper = [](Operation *op) {
    return isa<TaskOp, ConcurrentOp, YieldOp>(op);
  };
  for (Operation *from : anchors) {
    if (scheduleWrapper(from))
      continue;
    for (Operation *to : anchors) {
      if (scheduleWrapper(to))
        continue;
      if (graph.reaches(from, to)) {
        rel.edges.push_back(anchorId(from));
        rel.edges.push_back(anchorId(to));
      }
    }
  }
  MLIRContext *ctx = func.getContext();
  func->setAttr(kEdges, DenseI64ArrayAttr::get(ctx, rel.edges));
  func->setAttr(kLocalizes, DenseI64ArrayAttr::get(ctx, rel.localizes));
  func->setAttr(kCollectives, DenseI64ArrayAttr::get(ctx, rel.collectives));
}

static void wrapCollective(Operation *collective) {
  if (collective->getParentOfType<TaskOp>())
    return;
  auto mesh = meshSizeOf(gridOf(collective));
  if (!mesh || *mesh <= 1)
    return;

  OpBuilder builder(collective);
  auto task = TaskOp::create(builder, collective->getLoc(),
                             TokenType::get(collective->getContext()),
                             TypeRange{collective->getResult(0).getType()});
  Block *body = new Block();
  task.getBody().push_back(body);
  collective->moveBefore(body, body->end());
  Value result = collective->getResult(0);
  OpBuilder atEnd = OpBuilder::atBlockEnd(body);
  auto yield = YieldOp::create(atEnd, collective->getLoc(), ValueRange{result});
  Value exported = task.getValues().front();
  for (OpOperand &use : llvm::make_early_inc_range(result.getUses())) {
    if (use.getOwner() == yield)
      continue;
    use.set(exported);
  }
}

static llvm::DenseMap<int64_t, Operation *> anchorsOf(func::FuncOp func) {
  llvm::DenseMap<int64_t, Operation *> byId;
  func.walk([&](Operation *op) {
    int64_t id = anchorId(op);
    if (id > 0)
      byId[id] = op;
  });
  return byId;
}

static void repairAsync(func::FuncOp func) {
  auto edges = func->getAttrOfType<DenseI64ArrayAttr>(kEdges);
  if (!edges)
    return;
  auto byId = anchorsOf(func);
  llvm::SmallDenseSet<Operation *, 8> waited;
  for (size_t i = 0; i + 1 < edges.asArrayRef().size(); i += 2) {
    Operation *src = byId.lookup(edges.asArrayRef()[i]);
    Operation *dst = byId.lookup(edges.asArrayRef()[i + 1]);
    if (!src || !dst)
      continue;
    auto task = src->getParentOfType<TaskOp>();
    if (!task || dst->getParentOfType<TaskOp>() == task)
      continue;
    if (!exec::textuallyBefore(task, dst) || waited.contains(dst))
      continue;
    exec::HBGraph graph;
    exec::buildHbD(func, graph);
    if (graph.reaches(src, dst))
      continue;
    OpBuilder builder(dst);
    WaitOp::create(builder, dst->getLoc(), ValueRange{task.getToken()});
    waited.insert(dst);
  }
}

static void forwardYields(func::FuncOp func) {
  auto forward = [](ValueRange inners, ValueRange outers) {
    for (auto [inner, outer] : llvm::zip(inners, outers)) {
      if (inner != outer)
        outer.replaceAllUsesWith(inner);
    }
  };
  func.walk([&](Operation *op) {
    if (auto task = dyn_cast<TaskOp>(op)) {
      if (task.getBody().empty())
        return;
      auto yield = dyn_cast<YieldOp>(task.getBody().front().getTerminator());
      if (yield)
        forward(yield.getOperands(), task.getValues());
    } else if (auto conc = dyn_cast<ConcurrentOp>(op)) {
      if (conc.getBody().empty())
        return;
      auto yield = dyn_cast<YieldOp>(conc.getBody().front().getTerminator());
      if (yield)
        forward(yield.getOperands(), conc.getResults());
    }
  });
}

static void collectActions(Operation *op, SmallVectorImpl<Operation *> &actions) {
  if (auto task = dyn_cast<TaskOp>(op)) {
    if (task.getBody().empty())
      return;
    for (Operation &inner : task.getBody().front().without_terminator())
      collectActions(&inner, actions);
    return;
  }
  if (auto conc = dyn_cast<ConcurrentOp>(op)) {
    if (conc.getBody().empty())
      return;
    for (Operation &inner : conc.getBody().front().without_terminator())
      collectActions(&inner, actions);
    return;
  }
  actions.push_back(op);
}

static LogicalResult flattenSchedules(func::FuncOp func, const exec::HBGraph &source) {
  if (func.getBody().empty() || !llvm::hasSingleElement(func.getBody()))
    return success();
  forwardYields(func);
  SmallVector<Operation *> actions;
  for (Operation &op : func.getBody().front().without_terminator())
    collectActions(&op, actions);
  exec::HBGraph order = source;
  llvm::DenseSet<Operation *> actionSet;
  for (Operation *op : actions)
    actionSet.insert(op);
  for (Operation *op : actions) {
    for (Value value : op->getOperands()) {
      if (Operation *def = value.getDefiningOp())
        if (actionSet.contains(def))
          order.addEdge(def, op);
    }
  }
  SmallVector<Operation *> ordered;
  if (!exec::linearExtension(actions, order, ordered))
    return func.emitOpError("sync lowering is not a linear extension");
  Operation *term = func.getBody().front().getTerminator();
  for (Operation *op : ordered)
    op->moveBefore(term);

  SmallVector<Operation *> wrappers;
  func.walk<WalkOrder::PostOrder>([&](Operation *op) {
    if (isa<TaskOp, ConcurrentOp>(op))
      wrappers.push_back(op);
  });
  for (Operation *op : wrappers) {
    if (!op->use_empty())
      return op->emitOpError("sync lowering left a schedule result");
    op->erase();
  }
  return success();
}

static void stripRelation(func::FuncOp func) {
  func.walk([&](Operation *op) { op->removeAttr(kAnchor); });
  func->removeAttr(kEdges);
  func->removeAttr(kLocalizes);
  func->removeAttr(kCollectives);
}

static Operation *firstCollective(func::FuncOp func, ArrayRef<int64_t> collectiveIds,
                                  const llvm::DenseMap<int64_t, Operation *> &byId) {
  for (int64_t id : collectiveIds) {
    if (Operation *op = byId.lookup(id))
      return op;
  }
  Operation *found = nullptr;
  func.walk([&](Operation *op) {
    if (!found && exec::isV0Collective(op))
      found = op;
  });
  return found;
}

static LogicalResult checkContribution(func::FuncOp func, bool sync,
                                      const exec::HBGraph &graph) {
  auto ordered = [&](Operation *before, Operation *after) {
    return sync ? exec::textuallyBefore(before, after) : graph.reaches(before, after);
  };
  SmallVector<Operation *> collectives;
  func.walk([&](Operation *op) {
    if (exec::isV0Collective(op))
      collectives.push_back(op);
  });
  for (Operation *collective : collectives) {
    auto unpack = collective->getOperand(0).getDefiningOp<UnpackOp>();
    auto rank = unpack ? exec::ownerRank(unpack.getBuffer()) : std::nullopt;
    if (!unpack || !rank)
      return collective->emitOpError(
          "collective operand is not this rank's local tensor");
    bool sawPack = false;
    bool packBefore = false;
    func.walk([&](PackOp pack) {
      if (pack.getBuffer() != unpack.getBuffer())
        return;
      if (exec::isCollectiveImage(pack.getValue(), collective))
        return;
      auto owner = exec::ownerRank(pack.getBuffer());
      if (!owner || *owner != *rank)
        return;
      sawPack = true;
      if (ordered(pack, collective))
        packBefore = true;
    });
    if (sawPack && !packBefore)
      return collective->emitOpError("rank pack does not enter the collective");

    bool sawResult = false;
    std::optional<LogicalResult> fault;
    func.walk([&](PackOp pack) {
      if (fault || !exec::isCollectiveImage(pack.getValue(), collective))
        return;
      auto owner = exec::ownerRank(pack.getBuffer());
      if (!owner || *owner != *rank)
        return;
      sawResult = true;
      if (!ordered(collective, pack))
        fault = pack.emitOpError("collective result is not valid");
    });
    if (fault)
      return *fault;
    if (!sawResult)
      return collective->emitOpError("collective drops a participant");
    func.walk([&](UnpackOp read) {
      if (fault)
        return;
      bool output = false;
      bool packed = false;
      for (Operation *user : read.getBuffer().getUsers()) {
        auto pack = dyn_cast<PackOp>(user);
        if (!pack || pack.getBuffer() != read.getBuffer())
          continue;
        if (!exec::isCollectiveImage(pack.getValue(), collective))
          continue;
        auto owner = exec::ownerRank(pack.getBuffer());
        if (!owner || *owner != *rank)
          continue;
        output = true;
        if (ordered(pack, read))
          packed = true;
      }
      if (output && !packed)
        fault = read.emitOpError("collective result is not valid");
    });
    if (fault)
      return *fault;
  }
  return success();
}

static LogicalResult checkRecorded(func::FuncOp func, const exec::HBGraph &graph,
                                  bool sync) {
  auto edges = func->getAttrOfType<DenseI64ArrayAttr>(kEdges);
  auto localizes = func->getAttrOfType<DenseI64ArrayAttr>(kLocalizes);
  auto collectives = func->getAttrOfType<DenseI64ArrayAttr>(kCollectives);
  if (!edges)
    return success();
  auto byId = anchorsOf(func);
  Operation *collective = firstCollective(
      func, collectives ? collectives.asArrayRef() : ArrayRef<int64_t>{}, byId);
  auto failOn = [&](Operation *op, const char *sentence) {
    if (!op)
      op = func;
    return op->emitOpError(sentence);
  };
  if (localizes) {
    for (int64_t id : localizes.asArrayRef()) {
      if (!byId.lookup(id))
        return failOn(collective, "collective drops a participant");
    }
  }
  if (collectives) {
    for (int64_t id : collectives.asArrayRef()) {
      if (!byId.lookup(id))
        return failOn(func, "collective drops a participant");
    }
  }
  ArrayRef<int64_t> pairs = edges.asArrayRef();
  for (size_t i = 0; i + 1 < pairs.size(); i += 2) {
    Operation *src = byId.lookup(pairs[i]);
    Operation *dst = byId.lookup(pairs[i + 1]);
    if (!src || !dst)
      return failOn(collective ? collective : func, "missing cross-rank happens-before");
    bool kept = sync ? exec::textuallyBefore(src, dst) : graph.reaches(src, dst);
    if (!kept)
      return failOn(collective ? collective : src, "missing cross-rank happens-before");
  }
  return checkContribution(func, sync, graph);
}

static LogicalResult checkLoweredShape(func::FuncOp func, const exec::HBGraph &graph,
                                      bool sync) {
  SmallVector<Operation *> collectives;
  func.walk([&](Operation *op) {
    if (exec::isV0Collective(op))
      collectives.push_back(op);
  });
  auto ordered = [&](Operation *before, Operation *after) {
    return sync ? exec::textuallyBefore(before, after) : graph.reaches(before, after);
  };
  for (Operation *collective : collectives) {
    auto mesh = meshSizeOf(gridOf(collective));
    if (!mesh)
      continue;
    for (int64_t rank = 0; rank < *mesh; ++rank) {
      bool hasLocalize = false;
      bool hasInput = false;
      bool hasResult = false;
      func.walk([&](LocalizeOp localize) {
        if (static_cast<int64_t>(localize.getRank()) == rank)
          hasLocalize = true;
      });
      func.walk([&](PackOp pack) {
        auto owner = exec::ownerRank(pack.getBuffer());
        if (!owner || *owner != rank)
          return;
        if (exec::isCollectiveImage(pack.getValue(), collective))
          hasResult = true;
        else if (pack.getValue().getType() == collective->getOperand(0).getType())
          hasInput = true;
      });
      if (!hasLocalize || !hasInput || !hasResult)
        return collective->emitOpError("collective drops a participant");
    }

    Type inputType = collective->getOperand(0).getType();
    for (int64_t rank = 0; rank < *mesh; ++rank) {
      bool sawPack = false;
      bool packBefore = false;
      func.walk([&](PackOp pack) {
        auto owner = exec::ownerRank(pack.getBuffer());
        if (!owner || *owner != rank)
          return;
        if (exec::isCollectiveImage(pack.getValue(), collective))
          return;
        if (pack.getValue().getType() != inputType)
          return;
        sawPack = true;
        if (ordered(pack, collective))
          packBefore = true;
      });
      if (sawPack && !packBefore)
        return collective->emitOpError("missing cross-rank happens-before");

      std::optional<LogicalResult> fault;
      func.walk([&](PackOp pack) {
        if (fault)
          return;
        auto owner = exec::ownerRank(pack.getBuffer());
        if (!owner || *owner != rank)
          return;
        if (!exec::isCollectiveImage(pack.getValue(), collective))
          return;
        if (!ordered(collective, pack))
          fault = collective->emitOpError("missing cross-rank happens-before");
      });
      if (fault)
        return *fault;
      func.walk([&](UnpackOp unpack) {
        if (fault)
          return;
        auto owner = exec::ownerRank(unpack.getBuffer());
        if (!owner || *owner != rank)
          return;
        bool resultBuffer = false;
        for (Operation *user : unpack.getBuffer().getUsers()) {
          auto pack = dyn_cast<PackOp>(user);
          if (pack && exec::isCollectiveImage(pack.getValue(), collective))
            resultBuffer = true;
        }
        if (resultBuffer && !ordered(collective, unpack))
          fault = collective->emitOpError("missing cross-rank happens-before");
      });
      if (fault)
        return *fault;
    }
  }
  return success();
}

struct LowerS2C2HbD : impl::LowerS2C2HbDBase<LowerS2C2HbD> {
  using impl::LowerS2C2HbDBase<LowerS2C2HbD>::LowerS2C2HbDBase;

  void runOnOperation() override {
    if (mode != "async" && mode != "sync") {
      getOperation().emitError("hb-d mode must be async or sync");
      signalPassFailure();
      return;
    }
    for (func::FuncOp func : getOperation().getOps<func::FuncOp>()) {
      if (!hasCollective(func))
        continue;
      SourceRelation rel;
      assignAnchors(func, rel);
      exec::HBGraph graph;
      exec::buildHbD(func, graph);
      recordEdges(func, graph, rel);
      if (mode == "sync") {
        if (failed(flattenSchedules(func, graph)))
          signalPassFailure();
        continue;
      }
      SmallVector<Operation *> collectives;
      func.walk([&](Operation *op) {
        if (exec::isV0Collective(op))
          collectives.push_back(op);
      });
      for (Operation *collective : collectives)
        wrapCollective(collective);
      repairAsync(func);
    }
  }
};

struct CheckS2C2HbDFidelity
    : impl::CheckS2C2HbDFidelityBase<CheckS2C2HbDFidelity> {
  using impl::CheckS2C2HbDFidelityBase<CheckS2C2HbDFidelity>::CheckS2C2HbDFidelityBase;

  void runOnOperation() override {
    if (mode != "async" && mode != "sync") {
      getOperation().emitError("hb-d mode must be async or sync");
      signalPassFailure();
      return;
    }
    bool sync = mode == "sync";
    ModuleOp module = getOperation();
    bool sawFault = false;
    for (func::FuncOp func : module.getOps<func::FuncOp>()) {
      exec::HBGraph graph;
      exec::buildHbD(func, graph);
      LogicalResult result = func->hasAttr(kEdges)
                                 ? checkRecorded(func, graph, sync)
                                 : checkLoweredShape(func, graph, sync);
      stripRelation(func);
      if (failed(result))
        sawFault = true;
    }
    if (sawFault)
      signalPassFailure();
  }
};
} // namespace
} // namespace mlir::s2c2
