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
#include "s2c2/ExecutionModel/CollectiveDependency.h"
#include "s2c2/ExecutionModel/EventDependency.h"
#include "s2c2/ExecutionModel/HBGraph.h"
#include "s2c2/ExecutionModel/RankContext.h"
#include "s2c2/ExecutionModel/ValidityAnalysis.h"
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
#include "llvm/Support/raw_ostream.h"

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

static std::optional<bool> shardingReplicated(Operation *emitOn, Value buffer) {
  Value obj = getLogicalObject(buffer);
  if (!obj)
    return std::nullopt;
  auto localize = obj.getDefiningOp<LocalizeOp>();
  if (!localize)
    return std::nullopt;
  RankedTensorType globalTy = payloadOf(localize.getGlobal());
  FailureOr<stor::LocalShard> tile = stor::localShardFor(
      emitOn, localize.getSharding(), globalTy, localize.getRank());
  if (failed(tile))
    return std::nullopt;
  return tile->replicated;
}

static LogicalResult checkFunction(func::FuncOp func) {
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

  if (failed(stor::checkLocalizeGroups(func)))
    return failure();

  SmallVector<LocalizeOp> localizes;
  func.walk([&](LocalizeOp localize) { localizes.push_back(localize); });
  SmallVector<std::pair<Value, Value>> shardGroups;
  for (LocalizeOp localize : localizes) {
    std::pair<Value, Value> key{localize.getGlobal(), localize.getSharding()};
    if (llvm::is_contained(shardGroups, key))
      continue;
    shardGroups.push_back(key);
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

  auto isCollectiveResult = [&](Value value) {
    for (Operation *collective : collectives)
      if (value == collective->getResult(0))
        return true;
    return false;
  };

  exec::HBGraph rankGraph;
  exec::buildHbD(func, rankGraph);

  // ParticipantExists is not ParticipantContributes. The operand has to be
  // this rank's unpack, and every rank's input pack has to be that operand.
  for (Operation *collective : collectives) {
    auto unpack = collective->getOperand(0).getDefiningOp<UnpackOp>();
    if (!unpack || !ownerRank(unpack.getBuffer()))
      return collective->emitOpError(
          "collective operand is not this rank's local tensor");
  }
  if (!collectives.empty()) {
    for (LocalizeOp localize : localizes) {
      int64_t rank = static_cast<int64_t>(localize.getRank());
      bool hasInputPack = false;
      bool entered = false;
      func.walk([&](PackOp pack) {
        auto owner = ownerRank(pack.getBuffer());
        if (!owner || *owner != rank)
          return;
        if (!isCollectiveResult(pack.getValue()))
          hasInputPack = true;
      });
      for (Operation *collective : collectives) {
        auto unpack = collective->getOperand(0).getDefiningOp<UnpackOp>();
        auto owner = unpack ? ownerRank(unpack.getBuffer()) : std::nullopt;
        if (owner && *owner == rank)
          entered = true;
      }
      if (hasInputPack && !entered)
        return collectives.front()->emitOpError(
            "rank pack does not enter the collective");
    }
  }

  for (Operation *collective : collectives) {
    auto unpack = collective->getOperand(0).getDefiningOp<UnpackOp>();
    if (!unpack)
      continue;
    std::optional<bool> inputReplicated =
        shardingReplicated(collective, unpack.getBuffer());
    std::optional<bool> resultReplicated;
    func.walk([&](PackOp pack) {
      if (pack.getValue() != collective->getResult(0))
        return;
      resultReplicated = shardingReplicated(collective, pack.getBuffer());
    });
    StringRef name = collective->getName().getStringRef();
    if (name == "shard.all_reduce") {
      if (inputReplicated && !*inputReplicated)
        return collective->emitOpError("all-reduce operands are not replicated");
      if (resultReplicated && !*resultReplicated)
        return collective->emitOpError("all-reduce result is not replicated");
    } else if (name == "shard.all_gather") {
      if (inputReplicated && *inputReplicated)
        return collective->emitOpError("all-gather input is not sharded");
      if (resultReplicated && !*resultReplicated)
        return collective->emitOpError("all-gather result is not replicated");
    } else if (name == "shard.reduce_scatter") {
      if (inputReplicated && !*inputReplicated)
        return collective->emitOpError(
            "reduce-scatter input is not replicated");
      if (resultReplicated && *resultReplicated)
        return collective->emitOpError("reduce-scatter result is not sharded");
    }
  }

  for (Operation *collective : collectives) {
    func.walk([&](UnpackOp unpack) {
      if (pairFault)
        return;
      if (!rankGraph.reaches(collective, unpack))
        return;
      bool output = false;
      bool packedResult = false;
      for (Operation *user : unpack.getBuffer().getUsers()) {
        auto pack = dyn_cast<PackOp>(user);
        if (!pack || pack.getBuffer() != unpack.getBuffer())
          continue;
        if (pack.getValue() != collective->getResult(0))
          continue;
        output = true;
        if (rankGraph.reaches(pack, unpack))
          packedResult = true;
      }
      // An input residency stays valid across the collective. Only a
      // residency that is packed with this collective's result is an output.
      if (output && !packedResult)
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
    auto consumed = collective->getOperand(0).getDefiningOp<UnpackOp>();
    auto rank = consumed ? ownerRank(consumed.getBuffer()) : std::nullopt;
    if (!rank)
      continue;
    bool hasResultPack = false;
    func.walk([&](PackOp pack) {
      auto owner = ownerRank(pack.getBuffer());
      if (!owner || *owner != *rank)
        return;
      if (pack.getValue() == collective->getResult(0))
        hasResultPack = true;
    });
    if (!hasResultPack)
      return collective->emitOpError("collective drops a participant");
  }

  for (Operation *collective : collectives) {
    auto consumed = collective->getOperand(0).getDefiningOp<UnpackOp>();
    if (!consumed)
      continue;
    auto rank = ownerRank(consumed.getBuffer());
    if (!rank)
      continue;
    bool sawPack = false;
    bool packBefore = false;
    func.walk([&](PackOp pack) {
      if (pack.getBuffer() != consumed.getBuffer())
        return;
      auto owner = ownerRank(pack.getBuffer());
      if (!owner || *owner != *rank)
        return;
      if (pack.getValue() == collective->getResult(0))
        return;
      sawPack = true;
      if (rankGraph.reaches(pack, collective))
        packBefore = true;
    });
    if (sawPack && !packBefore)
      return collective->emitOpError("missing cross-rank happens-before");
    func.walk([&](UnpackOp unpack) {
      if (pairFault)
        return;
      bool resultBuffer = false;
      for (Operation *user : unpack.getBuffer().getUsers()) {
        auto pack = dyn_cast<PackOp>(user);
        if (pack && pack.getValue() == collective->getResult(0))
          resultBuffer = true;
      }
      if (resultBuffer && !rankGraph.reaches(collective, unpack))
        pairFault =
            collective->emitOpError("missing cross-rank happens-before");
    });
  }
  if (pairFault)
    return *pairFault;

  std::optional<LogicalResult> compFault;
  func.walk([&](Operation *op) {
    if (compFault || !op->getName().getStringRef().starts_with("comp."))
      return;
    std::optional<int64_t> seen;
    for (Value value : op->getOperands()) {
      std::optional<int64_t> rank;
      if (auto unpack = value.getDefiningOp<UnpackOp>())
        rank = ownerRank(unpack.getBuffer());
      else if (Operation *def = value.getDefiningOp())
        if (def->getName().getStringRef().starts_with("comp."))
          rank = exec::rankOf(def);
      if (!rank)
        continue;
      if (!seen)
        seen = rank;
      else if (*seen != *rank)
        compFault = op->emitOpError("compute operands are on different ranks");
    }
  });
  if (compFault)
    return *compFault;

  if (collectives.empty())
    return success();

  exec::CollectiveMatch matched = exec::matchCollectiveInstances(func);
  if (matched.faultOp)
    return matched.faultOp->emitOpError(matched.message);

  auto directlyLinked = [&](Operation *from, Operation *to) {
    auto it = rankGraph.successors().find(from);
    if (it == rankGraph.successors().end())
      return false;
    return llvm::is_contained(it->second, to);
  };
  unsigned cross = 0;
  for (auto [leftIndex, left] : llvm::enumerate(matched.instances)) {
    for (auto [rightIndex, right] : llvm::enumerate(matched.instances)) {
      if (leftIndex == rightIndex)
        continue;
      for (const exec::CollectiveParticipant &src : left.participants) {
        for (const exec::CollectiveParticipant &dst : right.participants) {
          if (src.rank == dst.rank)
            continue;
          if (directlyLinked(src.input, dst.collective))
            ++cross;
          if (directlyLinked(src.collective, dst.collective))
            ++cross;
          for (Operation *out : dst.resultPacks)
            if (directlyLinked(src.collective, out))
              ++cross;
        }
      }
    }
  }
  if (cross)
    return func.emitOpError("collective instances are cross-linked");

  func.walk([&](WaitOp wait) {
    if (pairFault)
      return;
    for (Value token : wait.getTokens()) {
      auto task = token.getDefiningOp<TaskOp>();
      if (!task)
        continue;
      auto waited = exec::rankOf(task);
      if (!waited)
        continue;
      for (Operation *collective : collectives) {
        auto unpack = collective->getOperand(0).getDefiningOp<UnpackOp>();
        auto owner = unpack ? ownerRank(unpack.getBuffer()) : std::nullopt;
        if (!owner || *owner != *waited)
          continue;
        if (!exec::textuallyBefore(wait, collective))
          continue;
        if (!rankGraph.reaches(wait, collective))
          pairFault = wait.emitOpError(
              "task token is not HB-before the later collective");
      }
    }
  });
  if (pairFault)
    return *pairFault;

  if (matched.instances.size() >= 2) {
    llvm::errs() << "hb-d @" << func.getSymName()
                 << " instances=" << matched.instances.size()
                 << " cross-instance-edges=0\n";
  }
  return success();
}

struct CheckS2C2HbD : impl::CheckS2C2HbDBase<CheckS2C2HbD> {
  using impl::CheckS2C2HbDBase<CheckS2C2HbD>::CheckS2C2HbDBase;

  void runOnOperation() override {
    ModuleOp module = getOperation();
    exec::HBGraph graph;
    exec::buildProgramOrder(module, graph);
    if (exec::checkResidencyValidity(module, graph)) {
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
      if (mlir::failed(checkFunction(func)))
        sawFault = true;
    }
    if (sawFault)
      signalPassFailure();
  }
};
} // namespace
} // namespace mlir::s2c2
