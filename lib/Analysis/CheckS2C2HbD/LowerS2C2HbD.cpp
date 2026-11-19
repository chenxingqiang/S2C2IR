//===- LowerS2C2HbD.cpp - HB_D lowering fidelity ----------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// --lower-s2c2-hb-d=async keeps HB_source inside HB_target by wrapping a
// multi-rank collective in sched.task. MeshSize 1 is unchanged.
// --lower-s2c2-hb-d=sync emits a linear extension of HB_D.
// --check-s2c2-hb-d-fidelity rejects a dropped rank (F07) or a dropped
// source edge (F08). No device library and no runtime.

#include "s2c2/Comm/CommOps.h"
#include "s2c2/S2C2Passes.h"
#include "s2c2/Schedule/ScheduleOps.h"
#include "s2c2/Storage/StorageOps.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/Shard/IR/ShardOps.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/SmallVector.h"

#include <algorithm>
#include <limits>
#include <optional>

namespace mlir::s2c2 {
#define GEN_PASS_DEF_LOWERS2C2HBD
#define GEN_PASS_DEF_CHECKS2C2HBDFIDELITY
#include "s2c2/S2C2Passes.h.inc"

using sched::ConcurrentOp;
using sched::OverlapOp;
using sched::PipelineOp;
using sched::StageOp;
using sched::TaskOp;
using sched::TokenType;
using sched::WaitOp;
using sched::YieldOp;
using stor::LocalizeOp;
using stor::PackOp;
using stor::UnpackOp;
using stor::getLogicalObject;

namespace {
constexpr llvm::StringLiteral kAnchor("s2c2.hb_anchor");
constexpr llvm::StringLiteral kEdges("s2c2.hb_d_edges");
constexpr llvm::StringLiteral kLocalizes("s2c2.hb_d_localizes");
constexpr llvm::StringLiteral kCollectives("s2c2.hb_d_collectives");

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

static void walkSeq(Block &block, ArrayRef<Operation *> incoming,
                    SmallVectorImpl<Operation *> &outgoing, HBGraph &g);

static void walkOp(Operation *op, ArrayRef<Operation *> incoming,
                   SmallVectorImpl<Operation *> &outgoing, HBGraph &g) {
  if (auto task = dyn_cast<TaskOp>(op)) {
    SmallVector<Operation *> bodyOut;
    walkSeq(task.getBody().front(), incoming, bodyOut, g);
    g.addEdges(bodyOut, op);
    outgoing.assign(bodyOut.begin(), bodyOut.end());
    outgoing.push_back(op);
    return;
  }
  if (auto conc = dyn_cast<ConcurrentOp>(op)) {
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
  if (isa<WaitOp, comm::BarrierOp>(op)) {
    for (Value token : op->getOperands()) {
      if (Operation *def = token.getDefiningOp())
        g.addEdge(def, op);
    }
  }
  outgoing.assign({op});
}

static void walkSeq(Block &block, ArrayRef<Operation *> incoming,
                    SmallVectorImpl<Operation *> &outgoing, HBGraph &g) {
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

static void buildFunc(func::FuncOp func, HBGraph &g) {
  if (func.getBody().empty())
    return;
  SmallVector<Operation *> unused;
  walkSeq(func.getBody().front(), {}, unused, g);
}

static bool isV0Collective(Operation *op) {
  StringRef name = op->getName().getStringRef();
  return name == "shard.all_reduce" || name == "shard.all_gather" ||
         name == "shard.reduce_scatter";
}

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

static std::optional<int64_t> ownerRank(Value buffer) {
  Value obj = getLogicalObject(buffer);
  if (!obj)
    return std::nullopt;
  if (auto localize = obj.getDefiningOp<LocalizeOp>())
    return static_cast<int64_t>(localize.getRank());
  return std::nullopt;
}

static int depthOf(Operation *op) {
  int depth = 0;
  for (Operation *parent = op->getParentOp(); parent;
       parent = parent->getParentOp())
    ++depth;
  return depth;
}

// a → b in a linear extension when a's block ancestor is textually before
// b's, including when one of them sits inside a sched.task.
static bool textuallyBefore(Operation *a, Operation *b) {
  if (!a || !b || a == b)
    return false;
  while (depthOf(a) > depthOf(b))
    a = a->getParentOp();
  while (depthOf(b) > depthOf(a))
    b = b->getParentOp();
  if (!a || !b || a == b)
    return false;
  while (a->getBlock() != b->getBlock()) {
    a = a->getParentOp();
    b = b->getParentOp();
    if (!a || !b)
      return false;
  }
  return a->isBeforeInBlock(b);
}

static bool imagesCollective(Value value, Operation *collective) {
  if (!collective || value == collective->getResult(0))
    return static_cast<bool>(collective) && value == collective->getResult(0);
  Operation *def = value.getDefiningOp();
  auto throughYield = [&](ValueRange yielded, ValueRange results) {
    for (auto [inner, outer] : llvm::zip(yielded, results)) {
      if (outer == value && imagesCollective(inner, collective))
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

static bool hasCollective(func::FuncOp func) {
  bool found = false;
  func.walk([&](Operation *op) {
    if (isV0Collective(op))
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
    if (isV0Collective(op))
      rel.collectives.push_back(next);
    ++next;
  });
}

static void recordEdges(func::FuncOp func, const HBGraph &g, SourceRelation &rel) {
  SmallVector<Operation *> anchors;
  func.walk([&](Operation *op) {
    if (anchorId(op) > 0)
      anchors.push_back(op);
  });
  for (Operation *from : anchors) {
    for (Operation *to : anchors) {
      if (g.reaches(from, to)) {
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

static void linearize(func::FuncOp func, const HBGraph &g) {
  if (func.getBody().empty() || !llvm::hasSingleElement(func.getBody()))
    return;
  Block &block = func.getBody().front();
  SmallVector<Operation *> ops;
  for (Operation &op : block.without_terminator())
    ops.push_back(&op);
  if (ops.empty())
    return;

  llvm::DenseMap<Operation *, int> index;
  for (auto [i, op] : llvm::enumerate(ops))
    index[op] = static_cast<int>(i);

  SmallVector<SmallVector<int>> succ(ops.size());
  SmallVector<int> indeg(ops.size(), 0);
  for (auto [i, op] : llvm::enumerate(ops)) {
    auto it = g.succ.find(op);
    if (it == g.succ.end())
      continue;
    for (Operation *next : it->second) {
      auto found = index.find(next);
      if (found == index.end())
        continue;
      int dst = found->second;
      if (dst == static_cast<int>(i))
        continue;
      succ[i].push_back(dst);
      ++indeg[dst];
    }
  }

  SmallVector<int> ready;
  for (int i = 0, n = static_cast<int>(ops.size()); i < n; ++i)
    if (indeg[i] == 0)
      ready.push_back(i);

  SmallVector<int> order;
  while (!ready.empty()) {
    auto best = std::min_element(ready.begin(), ready.end());
    int chosen = *best;
    ready.erase(best);
    order.push_back(chosen);
    for (int dst : succ[chosen]) {
      if (--indeg[dst] == 0)
        ready.push_back(dst);
    }
  }
  if (order.size() != ops.size())
    return;

  Operation *term = block.getTerminator();
  for (int slot : order)
    ops[slot]->moveBefore(term);
}

static void wrapCollective(Operation *collective) {
  if (collective->getParentOfType<TaskOp>())
    return;
  auto mesh = meshSizeOf(gridOf(collective));
  // MeshSize 1 is the existing single-device program: no new task and no
  // cross-rank edge.
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
    if (!textuallyBefore(task, dst) || waited.contains(dst))
      continue;
    HBGraph g;
    buildFunc(func, g);
    if (g.reaches(src, dst))
      continue;
    OpBuilder builder(dst);
    WaitOp::create(builder, dst->getLoc(), ValueRange{task.getToken()});
    waited.insert(dst);
  }
}

static void stripRelation(func::FuncOp func) {
  func.walk([&](Operation *op) { op->removeAttr(kAnchor); });
  func->removeAttr(kEdges);
  func->removeAttr(kLocalizes);
  func->removeAttr(kCollectives);
}

static Operation *firstCollective(func::FuncOp func,
                                  ArrayRef<int64_t> collectiveIds,
                                  const llvm::DenseMap<int64_t, Operation *> &byId) {
  for (int64_t id : collectiveIds) {
    if (Operation *op = byId.lookup(id))
      return op;
  }
  Operation *found = nullptr;
  func.walk([&](Operation *op) {
    if (!found && isV0Collective(op))
      found = op;
  });
  return found;
}

static LogicalResult checkRecorded(func::FuncOp func, const HBGraph &g, bool sync) {
  auto edges = func->getAttrOfType<DenseI64ArrayAttr>(kEdges);
  auto localizes = func->getAttrOfType<DenseI64ArrayAttr>(kLocalizes);
  auto collectives = func->getAttrOfType<DenseI64ArrayAttr>(kCollectives);
  if (!edges)
    return success();
  auto byId = anchorsOf(func);
  Operation *collective =
      firstCollective(func, collectives ? collectives.asArrayRef() : ArrayRef<int64_t>{},
                      byId);
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
      return failOn(collective ? collective : func,
                    "missing cross-rank happens-before");
    bool kept = sync ? textuallyBefore(src, dst) : g.reaches(src, dst);
    if (!kept)
      return failOn(collective ? collective : src,
                    "missing cross-rank happens-before");
  }
  return success();
}

static LogicalResult checkLoweredShape(func::FuncOp func, const HBGraph &g, bool sync) {
  SmallVector<Operation *> collectives;
  func.walk([&](Operation *op) {
    if (isV0Collective(op))
      collectives.push_back(op);
  });
  auto ordered = [&](Operation *before, Operation *after) {
    return sync ? textuallyBefore(before, after) : g.reaches(before, after);
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
        auto owner = ownerRank(pack.getBuffer());
        if (!owner || *owner != rank)
          return;
        if (imagesCollective(pack.getValue(), collective))
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
        auto owner = ownerRank(pack.getBuffer());
        if (!owner || *owner != rank)
          return;
        if (imagesCollective(pack.getValue(), collective))
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
        auto owner = ownerRank(pack.getBuffer());
        if (!owner || *owner != rank)
          return;
        if (!imagesCollective(pack.getValue(), collective))
          return;
        if (!ordered(collective, pack))
          fault = collective->emitOpError("missing cross-rank happens-before");
      });
      if (fault)
        return *fault;
      func.walk([&](UnpackOp unpack) {
        if (fault)
          return;
        auto owner = ownerRank(unpack.getBuffer());
        if (!owner || *owner != rank)
          return;
        bool resultBuffer = false;
        for (Operation *user : unpack.getBuffer().getUsers()) {
          auto pack = dyn_cast<PackOp>(user);
          if (pack && imagesCollective(pack.getValue(), collective))
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
      HBGraph g;
      buildFunc(func, g);
      recordEdges(func, g, rel);
      if (mode == "sync") {
        linearize(func, g);
        continue;
      }
      SmallVector<Operation *> collectives;
      func.walk([&](Operation *op) {
        if (isV0Collective(op))
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
    HBGraph g;
    for (func::FuncOp func : module.getOps<func::FuncOp>())
      buildFunc(func, g);

    bool sawFault = false;
    for (func::FuncOp func : module.getOps<func::FuncOp>()) {
      LogicalResult result = func->hasAttr(kEdges)
                                 ? checkRecorded(func, g, sync)
                                 : checkLoweredShape(func, g, sync);
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
