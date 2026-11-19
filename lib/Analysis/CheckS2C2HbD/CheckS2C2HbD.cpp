//===- CheckS2C2HbD.cpp - Rank-indexed happens-before -----------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// HB_D is the frozen intra-rank happens-before, indexed by rank, plus the
// edges of a well-formed shard.all_reduce / all_gather / reduce_scatter.
// MeshSize 1 adds no cross-rank edge. No runtime and no token lowering.

#include "s2c2/Comm/CommOps.h"
#include "s2c2/DistributionCoverage.h"
#include "s2c2/S2C2Passes.h"
#include "s2c2/Schedule/ScheduleOps.h"
#include "s2c2/Storage/StorageOps.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/Shard/IR/ShardOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/SmallVector.h"

#include <limits>
#include <optional>

namespace mlir::s2c2 {
#define GEN_PASS_DEF_CHECKS2C2HBD
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
using stor::LocalizeOp;
using stor::MaterializeOp;
using stor::ObjectType;
using stor::PackOp;
using stor::TransferOp;
using stor::UnpackOp;
using stor::getLogicalObject;

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
  if (isa<WaitOp, BarrierOp>(op)) {
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

static bool checkFrozenExecution(ModuleOp module, const HBGraph &g) {
  SmallVector<std::pair<Operation *, Value>> reads;
  llvm::DenseMap<Value, SmallVector<Operation *>> syncWrites;
  SmallVector<std::pair<Value, Value>> eventWrites;

  module.walk([&](Operation *op) {
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

  bool aliased = true;
  while (aliased) {
    aliased = false;
    module.walk([&](Operation *op) {
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
        for (auto [from, to] : llvm::zip(yield.getOperands(), task.getValues()))
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
  return failed;
}

static bool isAllToAll(Operation *op) {
  return op->getName().getStringRef() == "shard.all_to_all";
}

static bool isV0Collective(Operation *op) {
  StringRef name = op->getName().getStringRef();
  return name == "shard.all_reduce" || name == "shard.all_gather" ||
         name == "shard.reduce_scatter";
}

static bool isOutsideCollective(Operation *op) {
  StringRef name = op->getName().getStringRef();
  return name == "shard.send" || name == "shard.recv" || name == "shard.reduce" ||
         name == "shard.broadcast" || name == "shard.gather" ||
         name == "shard.scatter" || name == "shard.shift" ||
         name == "shard.update_halo" || name == "shard.all_slice";
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

static ArrayRef<int16_t> gridAxes(Operation *op) {
  if (auto attr = op->getAttrOfType<DenseI16ArrayAttr>("grid_axes"))
    return attr.asArrayRef();
  return {};
}

static bool axesAreFullMesh(ArrayRef<int16_t> axes, int64_t gridRank) {
  if (static_cast<int64_t>(axes.size()) != gridRank || gridRank <= 0)
    return false;
  SmallVector<int16_t> sorted(axes.begin(), axes.end());
  llvm::sort(sorted);
  for (int64_t i = 0; i < gridRank; ++i)
    if (sorted[i] != i)
      return false;
  return true;
}

static std::optional<int64_t> ownerRank(Value buffer) {
  Value obj = getLogicalObject(buffer);
  if (!obj)
    return std::nullopt;
  if (auto localize = obj.getDefiningOp<LocalizeOp>())
    return static_cast<int64_t>(localize.getRank());
  return std::nullopt;
}

static bool isHbm(Value buffer) {
  auto ty = dyn_cast<stor::BufferType>(buffer.getType());
  return ty && ty.getSpace() == stor::Space::HBM;
}

static int hbmReplicas(func::FuncOp func, Value object) {
  int n = 0;
  func.walk([&](MaterializeOp materialize) {
    if (materialize.getObject() == object && isHbm(materialize.getBuffer()))
      ++n;
  });
  return n;
}

static RankedTensorType payloadOf(Value object) {
  auto ty = dyn_cast<ObjectType>(object.getType());
  if (!ty)
    return {};
  return dyn_cast<RankedTensorType>(ty.getPayloadType());
}

static bool shapesMatchCollective(Operation *op, int64_t meshSize) {
  auto inTy = dyn_cast<RankedTensorType>(op->getOperand(0).getType());
  auto outTy = dyn_cast<RankedTensorType>(op->getResult(0).getType());
  if (!inTy || !outTy || !inTy.hasStaticShape() || !outTy.hasStaticShape())
    return false;
  StringRef name = op->getName().getStringRef();
  if (name == "shard.all_reduce")
    return inTy == outTy;
  int64_t axis = -1;
  bool grow = false;
  if (auto gather = dyn_cast<shard::AllGatherOp>(op)) {
    axis = gather.getGatherAxis().getSExtValue();
    grow = true;
  } else if (auto scatter = dyn_cast<shard::ReduceScatterOp>(op)) {
    axis = scatter.getScatterAxis().getSExtValue();
    grow = false;
  } else {
    return false;
  }
  if (inTy.getRank() != outTy.getRank() || axis < 0 || axis >= inTy.getRank())
    return false;
  if (inTy.getElementType() != outTy.getElementType())
    return false;
  for (int64_t dim = 0; dim < inTy.getRank(); ++dim) {
    if (dim == axis)
      continue;
    if (inTy.getDimSize(dim) != outTy.getDimSize(dim))
      return false;
  }
  int64_t inDim = inTy.getDimSize(axis);
  int64_t outDim = outTy.getDimSize(axis);
  if (meshSize <= 0)
    return false;
  if (grow)
    return outDim == inDim * meshSize;
  return inDim == outDim * meshSize;
}

static LogicalResult checkFunction(func::FuncOp func, const HBGraph &g) {
  SmallVector<Operation *> collectives;
  bool sawToAll = false;
  Operation *toAll = nullptr;
  bool sawOutside = false;
  Operation *outside = nullptr;
  func.walk([&](Operation *op) {
    if (isAllToAll(op)) {
      sawToAll = true;
      toAll = op;
    } else if (isOutsideCollective(op)) {
      sawOutside = true;
      outside = op;
    } else if (isV0Collective(op)) {
      collectives.push_back(op);
    }
  });
  if (sawToAll)
    return toAll->emitOpError("all-to-all is v0.1");
  if (sawOutside)
    return outside->emitOpError(
        "collective is outside distributed semantics v0");

  for (Operation *collective : collectives) {
    if (auto unpack = collective->getOperand(0).getDefiningOp<UnpackOp>()) {
      Value obj = getLogicalObject(unpack.getBuffer());
      if (obj && !obj.getDefiningOp<LocalizeOp>() &&
          hbmReplicas(func, obj) >= 2)
        return collective->emitOpError(
            "HBM residencies are not mesh participants");
    }
  }

  for (Operation *collective : collectives) {
    shard::GridOp grid = gridOf(collective);
    auto mesh = meshSizeOf(grid);
    ArrayRef<int16_t> axes = gridAxes(collective);
    if (!grid || !mesh)
      return collective->emitOpError("rank is outside the mesh");
    if (!axes.empty() &&
        !axesAreFullMesh(axes, static_cast<int64_t>(grid.getShape().size())))
      return collective->emitOpError("rank is outside the mesh");
  }

  SmallVector<LocalizeOp> localizes;
  func.walk([&](LocalizeOp localize) { localizes.push_back(localize); });
  SmallVector<Value> shardings;
  for (LocalizeOp localize : localizes) {
    if (llvm::is_contained(shardings, localize.getSharding()))
      continue;
    shardings.push_back(localize.getSharding());
    RankedTensorType globalTy = payloadOf(localize.getGlobal());
    stor::LocalShard summary;
    if (failed(stor::diagnosePartition(func, localize.getSharding(), globalTy,
                                       summary)))
      return failure();
  }

  auto flagPair = [&](Operation *op, Value src, Value dst) -> LogicalResult {
    auto left = ownerRank(src);
    auto right = ownerRank(dst);
    if (left && right && *left != *right)
      return op->emitOpError("rank does not own this shard");
    if (!left && !right && getLogicalObject(src) &&
        getLogicalObject(src) == getLogicalObject(dst) && isHbm(src) &&
        isHbm(dst)) {
      bool wideMesh = false;
      func->getParentOfType<ModuleOp>().walk([&](shard::GridOp grid) {
        auto mesh = meshSizeOf(grid);
        if (mesh && *mesh > 1)
          wideMesh = true;
      });
      if (wideMesh && collectives.empty())
        return op->emitOpError("pairwise copy is not a collective");
    }
    return success();
  };
  std::optional<LogicalResult> pairFault;
  func.walk([&](Operation *op) {
    if (pairFault)
      return;
    if (auto copy = dyn_cast<CopyOp>(op)) {
      if (failed(flagPair(op, copy.getSrc(), copy.getDst())))
        pairFault = failure();
    } else if (auto stream = dyn_cast<StreamOp>(op)) {
      if (failed(flagPair(op, stream.getSrc(), stream.getDst())))
        pairFault = failure();
    }
  });
  if (pairFault)
    return *pairFault;

  for (Operation *collective : collectives) {
    if (gridAxes(collective).empty())
      return collective->emitOpError("empty grid_axes is not a collective");
  }

  for (LocalizeOp localize : localizes) {
    auto tile = stor::localShardFor(localize, localize.getSharding(),
                                    payloadOf(localize.getGlobal()),
                                    localize.getRank());
    if (mlir::failed(tile))
      return failure();
    if (!tile->replicated) {
      func.walk([&](PackOp pack) -> WalkResult {
        if (pairFault)
          return WalkResult::interrupt();
        auto owner = ownerRank(pack.getBuffer());
        if (!owner || *owner == static_cast<int64_t>(localize.getRank()))
          return WalkResult::advance();
        if (pack.getValue().getDefiningOp() == nullptr)
          return WalkResult::advance();
        if (auto unpack = pack.getValue().getDefiningOp<UnpackOp>()) {
          auto src = ownerRank(unpack.getBuffer());
          if (src && *src != *owner &&
              !isV0Collective(unpack.getBuffer().getDefiningOp()))
            pairFault = pack.emitOpError("rank does not own this shard");
        }
        return WalkResult::advance();
      });
    }
  }
  if (pairFault)
    return *pairFault;

  for (Operation *collective : collectives) {
    func.walk([&](UnpackOp unpack) {
      if (pairFault)
        return;
      if (!g.reaches(collective, unpack))
        return;
      bool packedResult = false;
      for (Operation *user : unpack.getBuffer().getUsers()) {
        auto pack = dyn_cast<PackOp>(user);
        if (!pack || pack.getBuffer() != unpack.getBuffer())
          continue;
        if (pack.getValue() == collective->getResult(0) &&
            g.reaches(pack, unpack))
          packedResult = true;
      }
      if (!packedResult)
        pairFault = unpack.emitOpError("collective result is not valid");
    });
  }
  if (pairFault)
    return *pairFault;

  for (Operation *collective : collectives) {
    shard::GridOp grid = gridOf(collective);
    int64_t mesh = *meshSizeOf(grid);
    if (!shapesMatchCollective(collective, mesh))
      return collective->emitOpError("local shape is not the shard tile");
    for (int64_t rank = 0; rank < mesh; ++rank) {
      bool hasLocalize = false;
      bool hasInputPack = false;
      bool hasResultPack = false;
      auto inputType = collective->getOperand(0).getType();
      for (LocalizeOp localize : localizes)
        if (static_cast<int64_t>(localize.getRank()) == rank)
          hasLocalize = true;
      func.walk([&](PackOp pack) {
        auto owner = ownerRank(pack.getBuffer());
        if (!owner || *owner != rank)
          return;
        if (pack.getValue().getType() == inputType &&
            pack.getValue() != collective->getResult(0))
          hasInputPack = true;
        if (pack.getValue() == collective->getResult(0))
          hasResultPack = true;
      });
      if (!hasLocalize || !hasInputPack || !hasResultPack)
        return collective->emitOpError("collective drops a participant");
    }
  }

  for (Operation *collective : collectives) {
    shard::GridOp grid = gridOf(collective);
    int64_t mesh = *meshSizeOf(grid);
    auto inputType = collective->getOperand(0).getType();
    for (int64_t rank = 0; rank < mesh; ++rank) {
      bool packBefore = false;
      bool sawPack = false;
      func.walk([&](PackOp pack) {
        auto owner = ownerRank(pack.getBuffer());
        if (!owner || *owner != rank)
          return;
        if (pack.getValue().getType() != inputType ||
            pack.getValue() == collective->getResult(0))
          return;
        sawPack = true;
        if (g.reaches(pack, collective))
          packBefore = true;
      });
      if (sawPack && !packBefore)
        return collective->emitOpError("missing cross-rank happens-before");
      func.walk([&](UnpackOp unpack) {
        if (pairFault)
          return;
        auto owner = ownerRank(unpack.getBuffer());
        if (!owner || *owner != rank)
          return;
        bool resultBuffer = false;
        for (Operation *user : unpack.getBuffer().getUsers()) {
          auto pack = dyn_cast<PackOp>(user);
          if (pack && pack.getValue() == collective->getResult(0))
            resultBuffer = true;
        }
        if (resultBuffer && !g.reaches(collective, unpack))
          pairFault = collective->emitOpError(
              "missing cross-rank happens-before");
      });
    }
  }
  if (pairFault)
    return *pairFault;
  return success();
}

struct CheckS2C2HbD : impl::CheckS2C2HbDBase<CheckS2C2HbD> {
  using impl::CheckS2C2HbDBase<CheckS2C2HbD>::CheckS2C2HbDBase;

  void runOnOperation() override {
    ModuleOp module = getOperation();
    HBGraph g;
    for (func::FuncOp func : module.getOps<func::FuncOp>()) {
      if (func.getBody().empty())
        continue;
      SmallVector<Operation *> unused;
      walkSeq(func.getBody().front(), {}, unused, g);
    }
    if (checkFrozenExecution(module, g)) {
      signalPassFailure();
      return;
    }

    bool distributed = false;
    module.walk([&](Operation *op) {
      if (isa<shard::GridOp>(op) || isV0Collective(op) || isAllToAll(op) ||
          isOutsideCollective(op))
        distributed = true;
    });
    if (!distributed)
      return;

    bool sawFault = false;
    for (func::FuncOp func : module.getOps<func::FuncOp>()) {
      if (mlir::failed(checkFunction(func, g)))
        sawFault = true;
    }
    if (sawFault)
      signalPassFailure();
  }
};
} // namespace
} // namespace mlir::s2c2
