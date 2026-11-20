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

#include "mlir/Dialect/SCF/IR/SCF.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"

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
