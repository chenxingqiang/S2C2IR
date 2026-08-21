//===- S2C2Cost.cpp - Hardware-agnostic cost score --------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// Score-only. Does not rewrite IR and does not redefine happens-before.
// Overlap credit requires unordered siblings AND device.canOverlap.
// Pipeline StageOrder is sequential in the score.
//
//===----------------------------------------------------------------------===//

#include "s2c2/Comm/CommOps.h"
#include "s2c2/Compute/ComputeOps.h"
#include "s2c2/S2C2Passes.h"
#include "s2c2/Schedule/ScheduleOps.h"
#include "s2c2/Storage/StorageOps.h"
#include "s2c2/Storage/StorageTypes.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/BuiltinTypes.h"
#include "llvm/Support/raw_ostream.h"

namespace mlir::s2c2 {
#define GEN_PASS_DEF_S2C2COST
#include "s2c2/S2C2Passes.h.inc"

using comm::BarrierOp;
using comm::CopyOp;
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
struct Cost {
  int64_t compute = 0;
  int64_t storage = 0;
  int64_t communication = 0;
  int64_t synchronization = 0;
  int64_t overlap = 0;

  Cost &operator+=(const Cost &o) {
    compute += o.compute;
    storage += o.storage;
    communication += o.communication;
    synchronization += o.synchronization;
    overlap += o.overlap;
    return *this;
  }

  int64_t total() const {
    int64_t t = compute + storage + communication + synchronization - overlap;
    return t < 0 ? 0 : t;
  }
};

struct DeviceProfile {
  StringRef name;
  int64_t computeThru;
  int64_t waitCost;
  bool canOverlap;
  int64_t bw[7];
};

static int64_t ceilDiv(int64_t n, int64_t d) {
  if (n <= 0 || d <= 0)
    return 0;
  return (n + d - 1) / d;
}

static const DeviceProfile *lookupDevice(StringRef name) {
  static const DeviceProfile kProfiles[] = {
      {"cpu", 1, 1, false, {32, 16, 4, 8, 1, 4, 2}},
      {"gpu", 8, 1, true, {64, 32, 8, 32, 1, 8, 4}},
      {"npu", 16, 1, true, {32, 64, 8, 16, 1, 16, 4}},
      {"cim", 32, 8, false, {16, 8, 4, 4, 1, 32, 2}},
  };
  for (const DeviceProfile &p : kProfiles)
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

static Space spaceOf(Value v) {
  if (auto buf = dyn_cast<BufferType>(v.getType()))
    return buf.getSpace();
  return Space::DRAM;
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

struct S2C2Cost : impl::S2C2CostBase<S2C2Cost> {
  using impl::S2C2CostBase<S2C2Cost>::S2C2CostBase;

  const DeviceProfile *dev = nullptr;

  Cost walkSeq(Block &block);
  Cost walkOp(Operation *op);

  void runOnOperation() override {
    dev = lookupDevice(device);
    if (!dev) {
      getOperation()->emitError("unknown cost device '")
          << device << "'; expected cpu, gpu, npu, or cim";
      signalPassFailure();
      return;
    }
    for (auto func : getOperation().getOps<func::FuncOp>()) {
      if (func.getBody().empty())
        continue;
      Cost c = walkSeq(func.getBody().front());
      llvm::errs() << "s2c2-cost device=" << dev->name
                   << " func=" << func.getName() << " compute=" << c.compute
                   << " storage=" << c.storage
                   << " communication=" << c.communication
                   << " synchronization=" << c.synchronization
                   << " overlap=" << c.overlap << " total=" << c.total()
                   << "\n";
    }
  }
};

Cost S2C2Cost::walkSeq(Block &block) {
  Cost acc;
  for (Operation &op : block.without_terminator())
    acc += walkOp(&op);
  return acc;
}

Cost S2C2Cost::walkOp(Operation *op) {
  if (auto task = dyn_cast<TaskOp>(op))
    return walkSeq(task.getBody().front());

  if (auto conc = dyn_cast<ConcurrentOp>(op)) {
    Cost work;
    int64_t computeW = 0;
    int64_t commW = 0;
    for (TaskOp task : conc.getBody().front().getOps<TaskOp>()) {
      Cost child = walkOp(task);
      work += child;
      computeW += child.compute;
      commW += child.communication;
    }
    if (dev->canOverlap) {
      int64_t credit = computeW < commW ? computeW : commW;
      work.overlap += credit;
    }
    return work;
  }

  if (auto pipe = dyn_cast<PipelineOp>(op)) {
    Cost acc;
    for (StageOp stage : pipe.getBody().front().getOps<StageOp>())
      acc += walkSeq(stage.getBody().front());
    return acc;
  }

  if (auto overlap = dyn_cast<OverlapOp>(op)) {
    Cost computeSide = walkSeq(overlap.getCompute().front());
    Cost commSide = walkSeq(overlap.getCommunicate().front());
    Cost work = computeSide;
    work += commSide;
    if (dev->canOverlap) {
      int64_t credit = computeSide.compute < commSide.communication
                           ? computeSide.compute
                           : commSide.communication;
      work.overlap += credit;
    }
    return work;
  }

  Cost leaf;
  if (isa<MaterializeOp, AllocOp>(op)) {
    leaf.storage += payloadBytes(op->getResult(0).getType());
    return leaf;
  }
  if (auto pack = dyn_cast<PackOp>(op)) {
    int64_t bytes = payloadBytes(pack.getBuffer().getType());
    leaf.communication += ceilDiv(bytes, linkBw(*dev, spaceOf(pack.getBuffer())));
    return leaf;
  }
  if (auto xfer = dyn_cast<TransferOp>(op)) {
    int64_t bytes = payloadBytes(xfer.getBuffer().getType());
    leaf.storage += bytes;
    leaf.communication +=
        ceilDiv(bytes, linkBw(*dev, spaceOf(xfer.getSource()),
                              spaceOf(xfer.getBuffer())));
    return leaf;
  }
  if (auto copy = dyn_cast<CopyOp>(op)) {
    int64_t bytes = payloadBytes(copy.getSrc().getType());
    leaf.communication +=
        ceilDiv(bytes, linkBw(*dev, spaceOf(copy.getSrc()),
                              spaceOf(copy.getDst())));
    return leaf;
  }
  if (auto stream = dyn_cast<StreamOp>(op)) {
    int64_t bytes = payloadBytes(stream.getSrc().getType());
    leaf.communication +=
        ceilDiv(bytes, linkBw(*dev, spaceOf(stream.getSrc()),
                              spaceOf(stream.getDst())));
    return leaf;
  }
  if (auto wait = dyn_cast<WaitOp>(op)) {
    int64_t n = wait.getNumOperands();
    if (n == 0)
      n = 1;
    leaf.synchronization += n * dev->waitCost;
    return leaf;
  }
  if (auto barrier = dyn_cast<BarrierOp>(op)) {
    int64_t n = barrier.getNumOperands();
    if (n == 0)
      n = 1;
    leaf.synchronization += n * dev->waitCost;
    return leaf;
  }
  if (auto ew = dyn_cast<ElemwiseOp>(op)) {
    leaf.compute += ceilDiv(numel(ew.getResult().getType()), dev->computeThru);
    return leaf;
  }
  if (auto mm = dyn_cast<MatmulOp>(op)) {
    leaf.compute +=
        ceilDiv(matmulFlops(mm.getLhs().getType(), mm.getRhs().getType()),
                dev->computeThru);
    return leaf;
  }
  if (auto mlp = dyn_cast<GatedMLPOp>(op)) {
    leaf.compute += ceilDiv(gatedMlpFlops(mlp), dev->computeThru);
    return leaf;
  }
  return leaf;
}
} // namespace
} // namespace mlir::s2c2
