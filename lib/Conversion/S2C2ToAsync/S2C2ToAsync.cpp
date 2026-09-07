//===- S2C2ToAsync.cpp - HB-preserving token lowering -----------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// Slice 1: !sched.token → !async.token and sched.wait → async.await.
// Slice 2: sched.concurrent → sibling async.execute (no invented HB).
// Pipeline: v0.1 StageOrder → chained execute + await (not unordered).
// Acceptance: HB-preserving lowering, not "async works".
// Valueless tasks are lowered by slice 1 only when their token is waited.
//
//===----------------------------------------------------------------------===//

#include "s2c2/Comm/CommOps.h"
#include "s2c2/S2C2Passes.h"
#include "s2c2/Schedule/ScheduleOps.h"

#include "mlir/Dialect/Async/IR/Async.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

namespace mlir::s2c2 {
#define GEN_PASS_DEF_CONVERTS2C2TOKENTOASYNC
#define GEN_PASS_DEF_CONVERTS2C2CONCURRENTTOASYNC
#define GEN_PASS_DEF_CONVERTS2C2PIPELINETOASYNC
#include "s2c2/S2C2Passes.h.inc"

using comm::BarrierOp;
using comm::CopyOp;
using comm::StreamOp;
using sched::ConcurrentOp;
using sched::PipelineOp;
using sched::StageOp;
using sched::TaskOp;
using sched::WaitOp;
using sched::YieldOp;

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

static bool isTokenProducer(Operation *op) {
  if (isa<StreamOp>(op))
    return true;
  if (auto copy = dyn_cast<CopyOp>(op))
    return copy.getNumResults() == 1;
  return false;
}

static bool isDefinedInsideTask(Value value, TaskOp task) {
  Region &body = task.getBody();
  if (Operation *def = value.getDefiningOp())
    return body.isAncestor(def->getParentRegion());
  if (auto arg = dyn_cast<BlockArgument>(value))
    return body.isAncestor(arg.getOwner()->getParent());
  return false;
}

static bool allOperandsExternalToTask(Operation *op, TaskOp task) {
  return llvm::all_of(op->getOperands(), [&](Value operand) {
    return !isDefinedInsideTask(operand, task);
  });
}

static Value emitMappedTokenProducer(OpBuilder &b, Operation *op,
                                     IRMapping &mapping) {
  if (auto stream = dyn_cast<StreamOp>(op)) {
    Value token = wrapCopyEvent(b, stream.getLoc(),
                                mapping.lookupOrDefault(stream.getSrc()),
                                mapping.lookupOrDefault(stream.getDst()));
    mapping.map(stream.getToken(), token);
    return token;
  }
  auto copy = cast<CopyOp>(op);
  Value token = wrapCopyEvent(b, copy.getLoc(),
                              mapping.lookupOrDefault(copy.getSrc()),
                              mapping.lookupOrDefault(copy.getDst()));
  mapping.map(copy.getToken(), token);
  return token;
}

static LogicalResult lowerWaitedValuelessTask(TaskOp task,
                                              IRRewriter &rewriter) {
  bool hasInnerWait = false;
  bool onlyTokenProducers = true;
  int tokenProducers = 0;
  Operation *singleProducer = nullptr;
  for (Operation &inner : task.getBody().front().without_terminator()) {
    if (isa<WaitOp>(inner))
      hasInnerWait = true;
    if (isTokenProducer(&inner)) {
      ++tokenProducers;
      singleProducer = &inner;
      continue;
    }
    onlyTokenProducers = false;
  }

  rewriter.setInsertionPoint(task);
  // A4 flatten only when the single transfer's operands are defined
  // outside the task. Task-local src/dst fall through to nested execute.
  if (!hasInnerWait && onlyTokenProducers && tokenProducers == 1 &&
      allOperandsExternalToTask(singleProducer, task)) {
    IRMapping unused;
    rewriter.replaceOp(task,
                       emitMappedTokenProducer(rewriter, singleProducer, unused));
    return success();
  }

  llvm::DenseSet<Value> awaited;
  SmallVector<Value> innerTokens;
  auto execute = rewriter.create<async::ExecuteOp>(
      task.getLoc(), TypeRange{}, ValueRange{}, ValueRange{},
      [&](OpBuilder &body, Location bodyLoc, ValueRange) {
        IRMapping mapping;
        for (Operation &inner : task.getBody().front().without_terminator()) {
          if (isTokenProducer(&inner)) {
            innerTokens.push_back(
                emitMappedTokenProducer(body, &inner, mapping));
            continue;
          }
          if (auto copy = dyn_cast<CopyOp>(inner)) {
            body.create<CopyOp>(
                copy.getLoc(), TypeRange{},
                ValueRange{mapping.lookupOrDefault(copy.getSrc()),
                           mapping.lookupOrDefault(copy.getDst())});
            continue;
          }
          if (auto wait = dyn_cast<WaitOp>(inner)) {
            for (Value token : wait.getTokens()) {
              Value mapped = mapping.lookupOrDefault(token);
              body.create<async::AwaitOp>(wait.getLoc(), mapped);
              awaited.insert(mapped);
            }
            continue;
          }
          body.clone(inner, mapping);
        }
        // Task completion includes unwaited inner events (PO inside the task).
        for (Value token : innerTokens) {
          if (awaited.insert(token).second)
            body.create<async::AwaitOp>(bodyLoc, token);
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

static bool isDefinedInTaskOutside(Value value, TaskOp task, Region &inner) {
  if (!isDefinedInsideTask(value, task))
    return false;
  if (Operation *def = value.getDefiningOp())
    return !inner.isAncestor(def->getParentRegion());
  if (auto arg = dyn_cast<BlockArgument>(value))
    return !inner.isAncestor(arg.getOwner()->getParent());
  return false;
}

static bool allCapturedValuesExternalToTask(async::ExecuteOp exec,
                                            TaskOp task) {
  bool ok = true;
  exec.walk([&](Operation *op) {
    for (Value operand : op->getOperands()) {
      if (isDefinedInTaskOutside(operand, task, exec.getBodyRegion()))
        ok = false;
    }
  });
  return ok;
}

static void mapExecuteResults(async::ExecuteOp oldExec,
                              async::ExecuteOp newExec, IRMapping &mapping) {
  mapping.map(oldExec.getToken(), newExec.getToken());
  for (auto [oldV, newV] :
       llvm::zip(oldExec.getBodyResults(), newExec.getBodyResults()))
    mapping.map(oldV, newV);
}

static void hoistExecute(IRRewriter &rewriter, async::ExecuteOp exec,
                         IRMapping &mapping) {
  auto newExec = cast<async::ExecuteOp>(rewriter.clone(*exec, mapping));
  mapExecuteResults(exec, newExec, mapping);
}

static void emitBlockInto(OpBuilder &body, Block &block, IRMapping &mapping,
                          SmallVectorImpl<Value> &innerTokens,
                          llvm::DenseSet<Value> &awaited,
                          SmallVectorImpl<Value> &yielded) {
  for (Operation &inner : block.without_terminator()) {
    if (isTokenProducer(&inner)) {
      innerTokens.push_back(emitMappedTokenProducer(body, &inner, mapping));
      continue;
    }
    if (auto exec = dyn_cast<async::ExecuteOp>(inner)) {
      auto newExec = cast<async::ExecuteOp>(body.clone(inner, mapping));
      mapExecuteResults(exec, newExec, mapping);
      innerTokens.push_back(newExec.getToken());
      continue;
    }
    if (auto copy = dyn_cast<CopyOp>(inner)) {
      body.create<CopyOp>(
          copy.getLoc(), TypeRange{},
          ValueRange{mapping.lookupOrDefault(copy.getSrc()),
                     mapping.lookupOrDefault(copy.getDst())});
      continue;
    }
    if (auto wait = dyn_cast<WaitOp>(inner)) {
      for (Value token : wait.getTokens()) {
        Value mapped = mapping.lookupOrDefault(token);
        body.create<async::AwaitOp>(wait.getLoc(), mapped);
        awaited.insert(mapped);
      }
      continue;
    }
    if (auto awaitOp = dyn_cast<async::AwaitOp>(inner)) {
      Value mapped = mapping.lookupOrDefault(awaitOp.getOperand());
      auto created = body.create<async::AwaitOp>(awaitOp.getLoc(), mapped);
      if (!awaitOp.getResultTypes().empty())
        mapping.map(awaitOp.getResult(), created.getResult());
      awaited.insert(mapped);
      continue;
    }
    body.clone(inner, mapping);
  }
  auto yield = cast<YieldOp>(block.getTerminator());
  for (Value value : yield.getOperands())
    yielded.push_back(mapping.lookupOrDefault(value));
}

static void emitTaskBodyInto(OpBuilder &body, TaskOp task, IRMapping &mapping,
                             SmallVectorImpl<Value> &innerTokens,
                             llvm::DenseSet<Value> &awaited,
                             SmallVectorImpl<Value> &yielded) {
  emitBlockInto(body, task.getBody().front(), mapping, innerTokens, awaited,
                yielded);
}

static LogicalResult lowerTaskAsConcurrentChild(IRRewriter &rewriter,
                                                TaskOp task,
                                                IRMapping &mapping) {
  bool hasInnerWait = false;
  bool onlyTokenProducers = true;
  int tokenProducers = 0;
  int leftoverExecutes = 0;
  Operation *singleProducer = nullptr;
  async::ExecuteOp leftoverExec;
  for (Operation &inner : task.getBody().front().without_terminator()) {
    if (isa<WaitOp, async::AwaitOp>(inner))
      hasInnerWait = true;
    if (isTokenProducer(&inner)) {
      ++tokenProducers;
      singleProducer = &inner;
      continue;
    }
    if (auto exec = dyn_cast<async::ExecuteOp>(inner)) {
      ++leftoverExecutes;
      leftoverExec = exec;
      continue;
    }
    onlyTokenProducers = false;
  }

  // A4 flatten: single transfer / leftover execute, no inner wait,
  // captured operands defined outside this task.
  if (!hasInnerWait && task.getValues().empty()) {
    if (onlyTokenProducers && tokenProducers == 1 && leftoverExecutes == 0 &&
        allOperandsExternalToTask(singleProducer, task)) {
      Value token = emitMappedTokenProducer(rewriter, singleProducer, mapping);
      mapping.map(task.getToken(), token);
      return success();
    }
    if (tokenProducers == 0 && leftoverExecutes == 1 && onlyTokenProducers &&
        allCapturedValuesExternalToTask(leftoverExec, task)) {
      auto newExec =
          cast<async::ExecuteOp>(rewriter.clone(*leftoverExec, mapping));
      mapExecuteResults(leftoverExec, newExec, mapping);
      mapping.map(task.getToken(), newExec.getToken());
      return success();
    }
  }

  SmallVector<Type> valueTypes(task.getValues().getTypes());
  auto execute = rewriter.create<async::ExecuteOp>(
      task.getLoc(), valueTypes, ValueRange{}, ValueRange{},
      [&](OpBuilder &body, Location bodyLoc, ValueRange) {
        llvm::DenseSet<Value> awaited;
        SmallVector<Value> innerTokens;
        SmallVector<Value> yielded;
        emitTaskBodyInto(body, task, mapping, innerTokens, awaited, yielded);
        for (Value token : innerTokens) {
          if (awaited.insert(token).second)
            body.create<async::AwaitOp>(bodyLoc, token);
        }
        body.create<async::YieldOp>(bodyLoc, yielded);
      });
  mapping.map(task.getToken(), execute.getToken());
  for (auto [oldV, newV] :
       llvm::zip(task.getValues(), execute.getBodyResults()))
    mapping.map(oldV, newV);
  return success();
}

static LogicalResult lowerConcurrent(ConcurrentOp concurrent,
                                     IRRewriter &rewriter) {
  rewriter.setInsertionPoint(concurrent);
  IRMapping mapping;
  for (Operation &child : concurrent.getBody().front().without_terminator()) {
    if (auto exec = dyn_cast<async::ExecuteOp>(child)) {
      hoistExecute(rewriter, exec, mapping);
      continue;
    }
    if (auto task = dyn_cast<TaskOp>(child)) {
      if (failed(lowerTaskAsConcurrentChild(rewriter, task, mapping)))
        return failure();
      continue;
    }
    return child.emitOpError(
        "concurrent child must be sched.task or async.execute");
  }

  auto yield = cast<YieldOp>(concurrent.getBody().front().getTerminator());
  SmallVector<Value> results;
  for (Value value : yield.getOperands()) {
    Value mapped = mapping.lookupOrDefault(value);
    if (isa<async::ValueType>(mapped.getType()))
      results.push_back(
          rewriter.create<async::AwaitOp>(concurrent.getLoc(), mapped)
              .getResult());
    else
      results.push_back(mapped);
  }
  rewriter.replaceOp(concurrent, results);
  return success();
}

struct ConvertS2C2ConcurrentToAsync
    : impl::ConvertS2C2ConcurrentToAsyncBase<ConvertS2C2ConcurrentToAsync> {
  using impl::ConvertS2C2ConcurrentToAsyncBase<
      ConvertS2C2ConcurrentToAsync>::ConvertS2C2ConcurrentToAsyncBase;

  void runOnOperation() override {
    IRRewriter rewriter(&getContext());
    SmallVector<ConcurrentOp> concs;
    getOperation()->walk([&](ConcurrentOp op) { concs.push_back(op); });
    for (ConcurrentOp concurrent : llvm::reverse(concs)) {
      rewriter.setInsertionPoint(concurrent);
      if (failed(lowerConcurrent(concurrent, rewriter))) {
        signalPassFailure();
        return;
      }
    }
  }
};

static LogicalResult lowerPipeline(PipelineOp pipe, IRRewriter &rewriter) {
  rewriter.setInsertionPoint(pipe);
  IRMapping mapping;
  Value prevToken;
  for (Operation &child : pipe.getBody().front().without_terminator()) {
    auto stage = dyn_cast<StageOp>(child);
    if (!stage)
      return child.emitOpError("pipeline body may only contain sched.stage");
    if (prevToken)
      rewriter.create<async::AwaitOp>(stage.getLoc(), prevToken);
    auto execute = rewriter.create<async::ExecuteOp>(
        stage.getLoc(), TypeRange{}, ValueRange{}, ValueRange{},
        [&](OpBuilder &body, Location bodyLoc, ValueRange) {
          llvm::DenseSet<Value> awaited;
          SmallVector<Value> innerTokens;
          SmallVector<Value> yielded;
          emitBlockInto(body, stage.getBody().front(), mapping, innerTokens,
                        awaited, yielded);
          for (Value token : innerTokens) {
            if (awaited.insert(token).second)
              body.create<async::AwaitOp>(bodyLoc, token);
          }
          body.create<async::YieldOp>(bodyLoc, yielded);
        });
    prevToken = execute.getToken();
  }
  if (prevToken)
    rewriter.create<async::AwaitOp>(pipe.getLoc(), prevToken);
  rewriter.eraseOp(pipe);
  return success();
}

struct ConvertS2C2PipelineToAsync
    : impl::ConvertS2C2PipelineToAsyncBase<ConvertS2C2PipelineToAsync> {
  using impl::ConvertS2C2PipelineToAsyncBase<
      ConvertS2C2PipelineToAsync>::ConvertS2C2PipelineToAsyncBase;

  void runOnOperation() override {
    IRRewriter rewriter(&getContext());
    SmallVector<PipelineOp> pipes;
    getOperation()->walk([&](PipelineOp op) { pipes.push_back(op); });
    for (PipelineOp pipe : llvm::reverse(pipes)) {
      rewriter.setInsertionPoint(pipe);
      if (failed(lowerPipeline(pipe, rewriter))) {
        signalPassFailure();
        return;
      }
    }
  }
};
} // namespace
} // namespace mlir::s2c2
