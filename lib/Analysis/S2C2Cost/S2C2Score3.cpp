//===- S2C2Score3.cpp - Frozen v0.3 CanonicalRealizationCost ----*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// Shared Score_3. Mechanical extract from --s2c2-cost-cp.
// Does not rewrite IR or redefine happens-before.
// Cost = T_HB + (T_full - T_HB) + C_capacity.
// Conflict edges follow an HB-consistent canonical topological order
// (IR rank is only a tie-break). That keeps G_full a DAG. Not a search.
// Does not change --s2c2-cost or --s2c2-cost-hb numbers.
//
//===----------------------------------------------------------------------===//

#include "s2c2/S2C2Score3.h"

#include "s2c2/Comm/CommOps.h"
#include "s2c2/Compute/ComputeOps.h"
#include "s2c2/Schedule/ScheduleOps.h"
#include "s2c2/Storage/StorageOps.h"
#include "s2c2/Storage/StorageTypes.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"

#include <algorithm>

namespace mlir::s2c2 {

using llvm::ArrayRef;
using llvm::SmallPtrSet;
using llvm::SmallPtrSetImpl;
using llvm::SmallVector;
using llvm::SmallVectorImpl;
using llvm::StringRef;

using comm::BarrierOp;
using comm::CopyOp;
using comm::Engine;
using comm::StreamOp;
using comp::ElemwiseOp;
using comp::GatedMLPOp;
using comp::MatmulOp;
using sched::ConcurrentOp;
using sched::OverlapOp;
using sched::PipelineOp;
using sched::StageOp;
using sched::TaskOp;
using sched::WaitOp;
using stor::AllocOp;
using stor::BufferType;
using stor::MaterializeOp;
using stor::PackOp;
using stor::Space;
using stor::TransferOp;

namespace {
enum class ResKind { Compute, DMA, Comm, IO, None };

struct DeviceProfile {
  StringRef name;
  int64_t computeThru;
  int64_t waitCost;
  int64_t bw[7];
  bool pairCap[4][4];
};

struct WorkItem {
  Operation *op = nullptr;
  ResKind kind = ResKind::None;
};

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

static int64_t ceilDiv(int64_t n, int64_t d) {
  if (n <= 0 || d <= 0)
    return 0;
  return (n + d - 1) / d;
}

static const DeviceProfile *lookupDevice(StringRef name) {
  static const bool kNone[4][4] = {};
  static const bool kGpu[4][4] = {
      {0, 1, 1, 1},
      {1, 0, 1, 1},
      {1, 1, 0, 1},
      {1, 1, 1, 0},
  };
  static const DeviceProfile kProfiles[] = {
      {"cpu", 1, 1, {32, 16, 4, 8, 1, 4, 2}, {}},
      {"gpu", 8, 1, {64, 32, 8, 32, 1, 8, 4}, {}},
      {"npu", 16, 1, {32, 64, 8, 16, 1, 16, 4}, {}},
      {"cim", 32, 8, {16, 8, 4, 4, 1, 32, 2}, {}},
  };
  static DeviceProfile filled[4];
  static bool ready = false;
  if (!ready) {
    for (int i = 0; i < 4; ++i)
      filled[i] = kProfiles[i];
    auto setMat = [](DeviceProfile &p, const bool m[4][4]) {
      for (int i = 0; i < 4; ++i)
        for (int j = 0; j < 4; ++j)
          p.pairCap[i][j] = m[i][j];
    };
    setMat(filled[0], kNone);
    setMat(filled[1], kGpu);
    setMat(filled[2], kGpu);
    setMat(filled[3], kNone);
    ready = true;
  }
  for (DeviceProfile &p : filled)
    if (p.name == name)
      return &p;
  return nullptr;
}

static int64_t payloadBytes(Type type) {
  if (auto buf = dyn_cast<BufferType>(type))
    type = buf.getSourceType();
  auto ranked = dyn_cast<RankedTensorType>(type);
  if (!ranked || !ranked.hasStaticShape())
    return 0;
  unsigned bits = ranked.getElementTypeBitWidth();
  if (bits % 8 != 0)
    return 0;
  return ranked.getNumElements() * static_cast<int64_t>(bits / 8);
}

static int64_t numel(Type type) {
  auto ranked = dyn_cast<RankedTensorType>(type);
  if (!ranked || !ranked.hasStaticShape())
    return 0;
  return ranked.getNumElements();
}

static Space spaceOf(Value v) {
  if (auto buf = dyn_cast<BufferType>(v.getType()))
    return buf.getSpace();
  return Space::DRAM;
}

static int64_t linkBw(const DeviceProfile &d, Space space) {
  unsigned idx = static_cast<unsigned>(space);
  if (idx >= 7)
    return 1;
  return d.bw[idx];
}

static int64_t linkBw(const DeviceProfile &d, Space src, Space dst) {
  int64_t a = linkBw(d, src);
  int64_t b = linkBw(d, dst);
  return a < b ? a : b;
}

static bool isIoSpace(Space s) {
  return s == Space::SSD || s == Space::Host;
}

static int64_t matmulFlops(Type lhs, Type rhs) {
  auto a = dyn_cast<RankedTensorType>(lhs);
  auto b = dyn_cast<RankedTensorType>(rhs);
  if (!a || !b || a.getRank() < 2 || b.getRank() < 2)
    return 0;
  if (!a.hasStaticShape() || !b.hasStaticShape())
    return 0;
  int64_t m = a.getDimSize(a.getRank() - 2);
  int64_t k = a.getDimSize(a.getRank() - 1);
  int64_t n = b.getDimSize(b.getRank() - 1);
  return 2 * m * n * k;
}

static int64_t gatedMlpFlops(GatedMLPOp op) {
  auto x = dyn_cast<RankedTensorType>(op.getInput().getType());
  auto wg = dyn_cast<RankedTensorType>(op.getGateWeight().getType());
  auto wd = dyn_cast<RankedTensorType>(op.getDownWeight().getType());
  if (!x || !wg || !wd || !x.hasStaticShape() || !wg.hasStaticShape() ||
      !wd.hasStaticShape())
    return 0;
  if (x.getRank() < 2 || wg.getRank() < 2 || wd.getRank() < 2)
    return 0;
  int64_t batch = x.getDimSize(0);
  int64_t k = x.getDimSize(x.getRank() - 1);
  int64_t h = wg.getDimSize(wg.getRank() - 1);
  int64_t n = wd.getDimSize(wd.getRank() - 1);
  return 4 * batch * k * h + 2 * batch * h * n + batch * h;
}

static ResKind moveKind(Value src, Value dst, bool dmaEngine) {
  if (isIoSpace(spaceOf(src)) || isIoSpace(spaceOf(dst)))
    return ResKind::IO;
  if (dmaEngine)
    return ResKind::DMA;
  return ResKind::Comm;
}

static bool isDmaEngine(StreamOp stream) {
  auto attr = stream.getEngineAttr();
  if (!attr)
    return false;
  return stream.getEngine() == Engine::DMA;
}

static void collectGraphNodes(
    const llvm::DenseMap<Operation *, SmallVector<Operation *, 2>> &succ,
    const llvm::DenseMap<Operation *, int64_t> &dur,
    SmallPtrSetImpl<Operation *> &nodes) {
  for (const auto &kv : dur) {
    if (kv.second > 0)
      nodes.insert(kv.first);
  }
  for (const auto &kv : succ) {
    nodes.insert(kv.first);
    for (Operation *n : kv.second)
      nodes.insert(n);
  }
}

/// HB-consistent order: Kahn, always emit the ready node with smallest IR
/// rank. Tie-break only; not a schedule search.
static bool canonicalTopoRank(
    const llvm::DenseMap<Operation *, SmallVector<Operation *, 2>> &succ,
    const llvm::DenseMap<Operation *, unsigned> &irRank,
    const SmallPtrSetImpl<Operation *> &nodes,
    llvm::DenseMap<Operation *, unsigned> &topo) {
  llvm::DenseMap<Operation *, unsigned> indeg;
  for (Operation *n : nodes)
    indeg[n] = 0;
  for (const auto &kv : succ) {
    if (!nodes.contains(kv.first))
      continue;
    for (Operation *n : kv.second)
      if (nodes.contains(n))
        indeg[n] += 1;
  }
  auto pickReady = [&]() -> Operation * {
    Operation *best = nullptr;
    unsigned bestIr = ~0u;
    for (Operation *n : nodes) {
      if (indeg.lookup(n) != 0 || topo.count(n))
        continue;
      unsigned ir = irRank.lookup(n);
      if (!best || ir < bestIr) {
        best = n;
        bestIr = ir;
      }
    }
    return best;
  };
  unsigned next = 0;
  while (Operation *u = pickReady()) {
    topo[u] = next++;
    auto it = succ.find(u);
    if (it == succ.end())
      continue;
    for (Operation *n : it->second)
      if (nodes.contains(n) && indeg[n] > 0)
        indeg[n] -= 1;
  }
  return topo.size() == nodes.size();
}

static bool longestPath(
    const llvm::DenseMap<Operation *, SmallVector<Operation *, 2>> &succ,
    const llvm::DenseMap<Operation *, int64_t> &dur, int64_t &out) {
  SmallPtrSet<Operation *, 32> nodes;
  collectGraphNodes(succ, dur, nodes);
  llvm::DenseMap<Operation *, unsigned> dummyIr;
  unsigned i = 0;
  for (Operation *n : nodes)
    dummyIr[n] = i++;
  llvm::DenseMap<Operation *, unsigned> topo;
  if (!canonicalTopoRank(succ, dummyIr, nodes, topo))
    return false;

  llvm::DenseMap<Operation *, SmallVector<Operation *, 2>> pred;
  for (const auto &kv : succ)
    for (Operation *n : kv.second)
      pred[n].push_back(kv.first);

  SmallVector<Operation *, 32> order(nodes.size());
  for (Operation *n : nodes)
    order[topo.lookup(n)] = n;

  llvm::DenseMap<Operation *, int64_t> dp;
  int64_t best = 0;
  for (Operation *v : order) {
    int64_t bestIn = 0;
    auto pit = pred.find(v);
    if (pit != pred.end()) {
      for (Operation *p : pit->second)
        if (nodes.contains(p))
          bestIn = std::max(bestIn, dp.lookup(p));
    }
    int64_t val = dur.lookup(v) + bestIn;
    dp[v] = val;
    best = std::max(best, val);
  }
  out = best;
  return true;
}

struct Score3Engine {
  const DeviceProfile *dev = nullptr;
  HBGraph hb;
  llvm::DenseMap<Operation *, int64_t> duration;
  llvm::DenseMap<Operation *, ResKind> kindOf;
  int64_t capacity = 0;

  void walkHBOp(Operation *op, ArrayRef<Operation *> incoming,
                SmallVectorImpl<Operation *> &outgoing);
  void walkHBSeq(Block &block, ArrayRef<Operation *> incoming,
                 SmallVectorImpl<Operation *> &outgoing);
  void buildHB(func::FuncOp func);
  void scoreLeaf(Operation *op);
  void collectLeaves(Operation *root);
  LogicalResult scoreFunc(func::FuncOp func, Score3 &out);
};

void Score3Engine::walkHBSeq(Block &block, ArrayRef<Operation *> incoming,
                             SmallVectorImpl<Operation *> &outgoing) {
  SmallVector<Operation *> frontier(incoming.begin(), incoming.end());
  for (Operation &op : block.without_terminator()) {
    SmallVector<Operation *> next;
    walkHBOp(&op, frontier, next);
    frontier = std::move(next);
  }
  if (Operation *term = block.getTerminator()) {
    hb.addEdges(frontier, term);
    outgoing.assign({term});
    return;
  }
  outgoing = std::move(frontier);
}

void Score3Engine::walkHBOp(Operation *op, ArrayRef<Operation *> incoming,
                            SmallVectorImpl<Operation *> &outgoing) {
  if (auto task = dyn_cast<TaskOp>(op)) {
    SmallVector<Operation *> bodyOut;
    walkHBSeq(task.getBody().front(), incoming, bodyOut);
    hb.addEdges(bodyOut, op);
    outgoing.assign(bodyOut.begin(), bodyOut.end());
    outgoing.push_back(op);
    return;
  }
  if (auto conc = dyn_cast<ConcurrentOp>(op)) {
    SmallVector<Operation *> join;
    for (TaskOp task : conc.getBody().front().getOps<TaskOp>()) {
      SmallVector<Operation *> taskOut;
      walkHBOp(task, incoming, taskOut);
      join.append(taskOut.begin(), taskOut.end());
    }
    hb.addEdges(join, op);
    outgoing = std::move(join);
    outgoing.push_back(op);
    return;
  }
  if (auto pipe = dyn_cast<PipelineOp>(op)) {
    SmallVector<Operation *> cur(incoming.begin(), incoming.end());
    for (StageOp stage : pipe.getBody().front().getOps<StageOp>()) {
      SmallVector<Operation *> stageOut;
      walkHBSeq(stage.getBody().front(), cur, stageOut);
      hb.addEdges(stageOut, stage);
      cur = std::move(stageOut);
      cur.push_back(stage);
    }
    hb.addEdges(cur, op);
    outgoing = std::move(cur);
    outgoing.push_back(op);
    return;
  }
  if (auto overlap = dyn_cast<OverlapOp>(op)) {
    SmallVector<Operation *> computeOut, commOut;
    walkHBSeq(overlap.getCompute().front(), incoming, computeOut);
    walkHBSeq(overlap.getCommunicate().front(), incoming, commOut);
    SmallVector<Operation *> join(computeOut.begin(), computeOut.end());
    join.append(commOut.begin(), commOut.end());
    hb.addEdges(join, op);
    outgoing = std::move(join);
    outgoing.push_back(op);
    return;
  }
  hb.addEdges(incoming, op);
  if (isa<WaitOp, BarrierOp>(op)) {
    for (Value token : op->getOperands())
      if (Operation *def = token.getDefiningOp())
        hb.addEdge(def, op);
  }
  outgoing.assign({op});
}

void Score3Engine::buildHB(func::FuncOp func) {
  hb = HBGraph();
  if (func.getBody().empty())
    return;
  SmallVector<Operation *> unused;
  walkHBSeq(func.getBody().front(), {}, unused);
}

void Score3Engine::scoreLeaf(Operation *op) {
  ResKind kind = ResKind::None;
  int64_t ticks = 0;
  if (isa<MaterializeOp, AllocOp>(op)) {
    capacity += payloadBytes(op->getResult(0).getType());
    return;
  }
  if (auto pack = dyn_cast<PackOp>(op)) {
    int64_t bytes = payloadBytes(pack.getBuffer().getType());
    ticks = ceilDiv(bytes, linkBw(*dev, spaceOf(pack.getBuffer())));
    kind = ResKind::Comm;
  } else if (auto xfer = dyn_cast<TransferOp>(op)) {
    int64_t bytes = payloadBytes(xfer.getBuffer().getType());
    capacity += bytes;
    ticks = ceilDiv(bytes, linkBw(*dev, spaceOf(xfer.getSource()),
                                  spaceOf(xfer.getBuffer())));
    kind = moveKind(xfer.getSource(), xfer.getBuffer(), false);
  } else if (auto copy = dyn_cast<CopyOp>(op)) {
    int64_t bytes = payloadBytes(copy.getSrc().getType());
    ticks = ceilDiv(bytes, linkBw(*dev, spaceOf(copy.getSrc()),
                                  spaceOf(copy.getDst())));
    kind = moveKind(copy.getSrc(), copy.getDst(), false);
  } else if (auto stream = dyn_cast<StreamOp>(op)) {
    int64_t bytes = payloadBytes(stream.getSrc().getType());
    ticks = ceilDiv(bytes, linkBw(*dev, spaceOf(stream.getSrc()),
                                  spaceOf(stream.getDst())));
    kind = moveKind(stream.getSrc(), stream.getDst(), isDmaEngine(stream));
  } else if (auto wait = dyn_cast<WaitOp>(op)) {
    int64_t n = wait.getNumOperands();
    if (n == 0)
      n = 1;
    ticks = n * dev->waitCost;
  } else if (auto barrier = dyn_cast<BarrierOp>(op)) {
    int64_t n = barrier.getNumOperands();
    if (n == 0)
      n = 1;
    ticks = n * dev->waitCost;
  } else if (auto ew = dyn_cast<ElemwiseOp>(op)) {
    ticks = ceilDiv(numel(ew.getResult().getType()), dev->computeThru);
    kind = ResKind::Compute;
  } else if (auto mm = dyn_cast<MatmulOp>(op)) {
    ticks = ceilDiv(matmulFlops(mm.getLhs().getType(), mm.getRhs().getType()),
                    dev->computeThru);
    kind = ResKind::Compute;
  } else if (auto mlp = dyn_cast<GatedMLPOp>(op)) {
    ticks = ceilDiv(gatedMlpFlops(mlp), dev->computeThru);
    kind = ResKind::Compute;
  }
  if (ticks > 0)
    duration[op] = ticks;
  if (kind != ResKind::None && ticks > 0)
    kindOf[op] = kind;
}

void Score3Engine::collectLeaves(Operation *root) {
  root->walk([&](Operation *op) {
    if (isa<TaskOp, ConcurrentOp, PipelineOp, StageOp, OverlapOp, func::FuncOp,
            ModuleOp>(op))
      return;
    scoreLeaf(op);
  });
}

LogicalResult Score3Engine::scoreFunc(func::FuncOp func, Score3 &out) {
  duration.clear();
  kindOf.clear();
  capacity = 0;
  buildHB(func);
  collectLeaves(func);

  llvm::DenseMap<Operation *, unsigned> irRank;
  unsigned walk = 0;
  func.walk([&](Operation *op) { irRank[op] = walk++; });

  SmallPtrSet<Operation *, 32> hbNodes;
  collectGraphNodes(hb.succ, duration, hbNodes);
  llvm::DenseMap<Operation *, unsigned> hbTopo;
  if (!canonicalTopoRank(hb.succ, irRank, hbNodes, hbTopo)) {
    func.emitError("happens-before graph is cyclic; cannot score");
    return failure();
  }

  SmallVector<WorkItem> items;
  func.walk([&](Operation *op) {
    auto it = kindOf.find(op);
    if (it == kindOf.end())
      return;
    items.push_back(WorkItem{op, it->second});
  });

  HBGraph full = hb;
  for (const WorkItem &a : items) {
    for (const WorkItem &b : items) {
      if (a.op == b.op)
        continue;
      if (hb.reaches(a.op, b.op) || hb.reaches(b.op, a.op))
        continue;
      unsigned i = static_cast<unsigned>(a.kind);
      unsigned j = static_cast<unsigned>(b.kind);
      if (i < 4 && j < 4 && dev->pairCap[i][j])
        continue;
      unsigned ra = hbTopo.lookup(a.op);
      unsigned rb = hbTopo.lookup(b.op);
      if (ra < rb)
        full.addEdge(a.op, b.op);
    }
  }

  int64_t tHB = 0;
  int64_t tFull = 0;
  if (!longestPath(hb.succ, duration, tHB) ||
      !longestPath(full.succ, duration, tFull)) {
    func.emitError("cost constraint graph is cyclic; not a DAG longest path");
    return failure();
  }
  int64_t contention = tFull - tHB;
  if (contention < 0)
    contention = 0;
  out.criticalPath = tHB;
  out.contention = contention;
  out.capacity = capacity;
  out.total = tFull + capacity;
  return success();
}
} // namespace

bool isKnownScore3Device(StringRef device) {
  return lookupDevice(device) != nullptr;
}

LogicalResult computeScore3(func::FuncOp program, StringRef device,
                            Score3 &out) {
  const DeviceProfile *dev = lookupDevice(device);
  if (!dev)
    return failure();
  Score3Engine eng;
  eng.dev = dev;
  return eng.scoreFunc(program, out);
}

} // namespace mlir::s2c2
