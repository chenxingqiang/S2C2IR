//===- S2C2ToAsync.cpp - HB-preserving token lowering -----------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// Slice 1: !sched.token → !async.token and sched.wait → async.await.
// Acceptance: HB-preserving lowering, not "async works".
// Valueless tasks are lowered only when their token is waited.
// Concurrent itself is not rewritten.
//
//===----------------------------------------------------------------------===//

#include "s2c2/Comm/CommOps.h"
#include "s2c2/S2C2Passes.h"
#include "s2c2/Schedule/ScheduleOps.h"

#include "mlir/Dialect/Async/IR/Async.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

namespace mlir::s2c2 {
#define GEN_PASS_DEF_CONVERTS2C2TOKENTOASYNC
#include "s2c2/S2C2Passes.h.inc"

using comm::BarrierOp;
using comm::CopyOp;
using comm::StreamOp;
using sched::TaskOp;
using sched::WaitOp;

namespace {
static bool isValuelessTask(TaskOp task) { return task.getValues().empty(); }

static bool taskTokenIsWaited(TaskOp task) {
  for (OpOperand &use : task.getToken().getUses())
    if (isa<WaitOp, BarrierOp>(use.getOwner()))
      return true;
  return false;
}

static bool insideWaitedValuelessTask(Operation *op) {
  auto task = op->getParentOfType<TaskOp>();
  return task && isValuelessTask(task) && taskTokenIsWaited(task);
}

static Value wrapCopyEvent(OpBuilder &b, Location loc, Value src, Value dst) {
  auto execute = b.create<async::ExecuteOp>(
      loc, TypeRange{}, ValueRange{}, ValueRange{},
      [&](OpBuilder &body, Location bodyLoc, ValueRange) {
        body.create<CopyOp>(bodyLoc, TypeRange{}, ValueRange{src, dst});
        body.create<async::YieldOp>(bodyLoc, ValueRange{});
      });
  return execute.getToken();
}

static LogicalResult lowerWaitedValuelessTask(TaskOp task,
                                              IRRewriter &rewriter) {
  auto execute = rewriter.create<async::ExecuteOp>(
      task.getLoc(), TypeRange{}, ValueRange{}, ValueRange{},
      [&](OpBuilder &body, Location bodyLoc, ValueRange) {
        IRMapping mapping;
        for (Operation &inner : task.getBody().front().without_terminator()) {
          if (auto stream = dyn_cast<StreamOp>(inner)) {
            body.create<CopyOp>(stream.getLoc(), TypeRange{},
                                ValueRange{stream.getSrc(), stream.getDst()});
            continue;
          }
          if (auto copy = dyn_cast<CopyOp>(inner)) {
            body.create<CopyOp>(copy.getLoc(), TypeRange{},
                                ValueRange{copy.getSrc(), copy.getDst()});
            continue;
          }
          if (auto wait = dyn_cast<WaitOp>(inner)) {
            for (Value token : wait.getTokens())
              body.create<async::AwaitOp>(wait.getLoc(),
                                          mapping.lookupOrDefault(token));
            continue;
          }
          body.clone(inner, mapping);
        }
        body.create<async::YieldOp>(bodyLoc, ValueRange{});
      });
  rewriter.replaceOp(task, execute.getToken());
  return success();
}

struct ConvertS2C2TokenToAsync
    : impl::ConvertS2C2TokenToAsyncBase<ConvertS2C2TokenToAsync> {
  using impl::ConvertS2C2TokenToAsyncBase<
      ConvertS2C2TokenToAsync>::ConvertS2C2TokenToAsyncBase;

  void runOnOperation() override {
    IRRewriter rewriter(&getContext());
    SmallVector<StreamOp> streams;
    SmallVector<CopyOp> tokenCopies;
    SmallVector<TaskOp> waitedEventTasks;
    getOperation()->walk([&](Operation *op) {
      if (auto stream = dyn_cast<StreamOp>(op)) {
        if (!insideWaitedValuelessTask(op))
          streams.push_back(stream);
      } else if (auto copy = dyn_cast<CopyOp>(op)) {
        if (copy.getNumResults() == 1 && !insideWaitedValuelessTask(op))
          tokenCopies.push_back(copy);
      } else if (auto task = dyn_cast<TaskOp>(op)) {
        if (isValuelessTask(task) && taskTokenIsWaited(task))
          waitedEventTasks.push_back(task);
      }
    });

    for (StreamOp stream : streams) {
      rewriter.setInsertionPoint(stream);
      Value token = wrapCopyEvent(rewriter, stream.getLoc(), stream.getSrc(),
                                  stream.getDst());
      rewriter.replaceOp(stream, token);
    }
    for (CopyOp copy : tokenCopies) {
      rewriter.setInsertionPoint(copy);
      Value token =
          wrapCopyEvent(rewriter, copy.getLoc(), copy.getSrc(), copy.getDst());
      rewriter.replaceOp(copy, token);
    }
    for (TaskOp task : llvm::reverse(waitedEventTasks)) {
      rewriter.setInsertionPoint(task);
      if (failed(lowerWaitedValuelessTask(task, rewriter))) {
        signalPassFailure();
        return;
      }
    }

    SmallVector<Operation *> waits;
    getOperation()->walk([&](Operation *op) {
      if (isa<WaitOp, BarrierOp>(op))
        waits.push_back(op);
    });
    for (Operation *op : llvm::reverse(waits)) {
      rewriter.setInsertionPoint(op);
      for (Value token : op->getOperands()) {
        if (!isa<async::TokenType>(token.getType())) {
          op->emitOpError("wait token was not converted to !async.token");
          signalPassFailure();
          return;
        }
        rewriter.create<async::AwaitOp>(op->getLoc(), token);
      }
      rewriter.eraseOp(op);
    }
  }
};
} // namespace
} // namespace mlir::s2c2
