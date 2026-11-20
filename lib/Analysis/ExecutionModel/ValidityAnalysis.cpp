//===- ValidityAnalysis.cpp - Residency reads need a reaching write -*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/ExecutionModel/ValidityAnalysis.h"
#include "s2c2/ExecutionModel/EventDependency.h"

#include "s2c2/Comm/CommOps.h"
#include "s2c2/Schedule/ScheduleOps.h"
#include "s2c2/Storage/StorageOps.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/Matchers.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"

using namespace mlir;
using namespace mlir::s2c2;
using namespace mlir::s2c2::exec;
using comm::CopyOp;
using comm::StreamOp;
using sched::ConcurrentOp;
using sched::TaskOp;
using sched::YieldOp;
using stor::PackOp;
using stor::TransferOp;
using stor::UnpackOp;

bool mlir::s2c2::exec::checkResidencyValidity(ModuleOp module,
                                             const HBGraph &graph) {
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
        for (auto [from, to] : llvm::zip(yield.getOperands(), conc.getResults()))
          copyWrites(from, to);
      } else if (auto ifOp = dyn_cast<scf::IfOp>(op)) {
        for (Region &region : ifOp->getRegions()) {
          if (region.empty())
            continue;
          auto yield = dyn_cast<scf::YieldOp>(region.front().getTerminator());
          if (!yield)
            continue;
          for (auto [from, to] : llvm::zip(yield.getOperands(), ifOp.getResults()))
            copyWrites(from, to);
        }
      } else if (auto sw = dyn_cast<scf::IndexSwitchOp>(op)) {
        for (Region &region : sw->getRegions()) {
          if (region.empty())
            continue;
          auto yield = dyn_cast<scf::YieldOp>(region.front().getTerminator());
          if (!yield)
            continue;
          for (auto [from, to] : llvm::zip(yield.getOperands(), sw.getResults()))
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
      if (graph.reaches(write, readOp)) {
        defined = true;
        break;
      }
    }
    if (!defined) {
      for (auto [token, dest] : eventWrites) {
        if (dest == residency && eventVisible(token, readOp, graph)) {
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

namespace {

using MustSet = llvm::SmallPtrSet<Value, 8>;

MustSet intersectMust(const MustSet &lhs, const MustSet &rhs) {
  MustSet out;
  for (Value value : lhs)
    if (rhs.contains(value))
      out.insert(value);
  return out;
}

std::optional<int64_t> constIndex(Value value) {
  APInt bits;
  if (!matchPattern(value, m_ConstantInt(&bits)))
    return std::nullopt;
  return bits.getSExtValue();
}

// nullopt: the trip count is not a constant, so zero iterations stay possible.
std::optional<bool> loopMustExecute(scf::ForOp forOp) {
  auto lower = constIndex(forOp.getLowerBound());
  auto upper = constIndex(forOp.getUpperBound());
  auto step = constIndex(forOp.getStep());
  if (!lower || !upper || !step || *step <= 0)
    return std::nullopt;
  return *upper > *lower;
}

struct Finder {
    UnpackOp target;
    bool found = false;
    bool valid = false;
    llvm::DenseMap<Value, SmallVector<Value, 1>> eventDst;
    void run(Block &block, MustSet &must) {
      for (Operation &op : block.without_terminator()) {
        if (found)
          return;
        if (&op == target.getOperation()) {
          found = true;
          valid = must.contains(target.getBuffer());
          return;
        }
        if (auto ifOp = dyn_cast<scf::IfOp>(op)) {
          MustSet incoming = must;
          APInt bits;
          bool known = matchPattern(ifOp.getCondition(), m_ConstantInt(&bits));
          auto branch = [&](Block *inner, MustSet local) {
            if (!inner || found)
              return local;
            run(*inner, local);
            return local;
          };
          MustSet thenSet = branch(ifOp.thenBlock(), incoming);
          MustSet elseSet = branch(ifOp.elseBlock(), incoming);
          if (found)
            return;
          if (known)
            must = bits.isZero() ? elseSet : thenSet;
          else
            must = intersectMust(thenSet, elseSet);
          continue;
        }
        if (auto sw = dyn_cast<scf::IndexSwitchOp>(op)) {
          MustSet incoming = must;
          auto branch = [&](Block &inner) {
            MustSet local = incoming;
            run(inner, local);
            return local;
          };
          if (std::optional<int64_t> selector = constIndex(sw.getArg())) {
            ArrayRef<int64_t> cases = sw.getCases();
            Block *taken = &sw.getDefaultBlock();
            for (auto [idx, value] : llvm::enumerate(cases)) {
              if (value == *selector)
                taken = &sw.getCaseBlock(idx);
            }
            MustSet chosen = branch(*taken);
            if (found)
              return;
            must = std::move(chosen);
            continue;
          }
          MustSet joined = branch(sw.getDefaultBlock());
          for (unsigned idx = 0, n = sw.getNumCases(); idx < n && !found; ++idx)
            joined = intersectMust(joined, branch(sw.getCaseBlock(idx)));
          if (found)
            return;
          must = std::move(joined);
          continue;
        }
        if (auto forOp = dyn_cast<scf::ForOp>(op)) {
          MustSet incoming = must;
          std::optional<bool> executes = loopMustExecute(forOp);
          if (executes == true && !forOp.getBodyRegion().empty()) {
            MustSet body = incoming;
            run(*forOp.getBody(), body);
            if (found)
              return;
            must = std::move(body);
          } else if (!forOp.getBodyRegion().empty()) {
            MustSet ignored = incoming;
            run(*forOp.getBody(), ignored);
            if (found)
              return;
            must = std::move(incoming);
          }
          continue;
        }
        if (auto overlap = dyn_cast<sched::OverlapOp>(op)) {
          MustSet incoming = must;
          MustSet compute = incoming;
          MustSet communicate = incoming;
          if (!overlap.getCompute().empty())
            run(overlap.getCompute().front(), compute);
          if (found)
            return;
          if (!overlap.getCommunicate().empty())
            run(overlap.getCommunicate().front(), communicate);
          if (found)
            return;
          must = std::move(compute);
          must.insert(communicate.begin(), communicate.end());
          continue;
        }
        if (op.getNumRegions() == 0) {
          if (auto pack = dyn_cast<PackOp>(op))
            must.insert(pack.getBuffer());
          else if (auto stream = dyn_cast<StreamOp>(op))
            eventDst[stream.getToken()].push_back(stream.getDst());
          else if (auto wait = dyn_cast<sched::WaitOp>(op)) {
            for (Value token : wait.getTokens())
              for (Value buffer : eventDst.lookup(token))
                must.insert(buffer);
          }
          continue;
        }
        for (Region &region : op.getRegions()) {
          if (!region.empty())
            run(region.front(), must);
          if (found)
            return;
        }
      }
    }
  };

} // namespace

bool mlir::s2c2::exec::inputPackIsMustValid(UnpackOp unpack) {
  auto func = unpack->getParentOfType<func::FuncOp>();
  if (!func || func.getBody().empty())
    return false;
  Finder finder;
  finder.target = unpack;
  MustSet state;
  finder.run(func.getBody().front(), state);
  return finder.found && finder.valid;
}
