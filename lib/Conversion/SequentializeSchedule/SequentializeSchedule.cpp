//===- SequentializeSchedule.cpp - Inline S2C2 schedule regions -*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/Comm/CommOps.h"
#include "s2c2/S2C2Passes.h"
#include "s2c2/Schedule/ScheduleOps.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "llvm/ADT/SmallVector.h"

namespace mlir::s2c2 {
#define GEN_PASS_DEF_SEQUENTIALIZES2C2SCHEDULE
#include "s2c2/S2C2Passes.h.inc"

using comm::BarrierOp;
using sched::ConcurrentOp;
using sched::OverlapOp;
using sched::PipelineOp;
using sched::StageOp;
using sched::TaskOp;
using sched::WaitOp;
using sched::YieldOp;

namespace {
static LogicalResult inlineRegionDropYield(PatternRewriter &rewriter,
                                           Region &region, Operation *at) {
  if (region.empty())
    return failure();
  Block *block = &region.front();
  auto yield = dyn_cast<YieldOp>(block->getTerminator());
  if (!yield)
    return failure();
  rewriter.inlineBlockBefore(block, at);
  rewriter.eraseOp(yield);
  return success();
}

static LogicalResult inlineTaskAt(PatternRewriter &rewriter, TaskOp task) {
  Block *body = &task.getBody().front();
  auto yield = dyn_cast<YieldOp>(body->getTerminator());
  if (!yield)
    return failure();
  SmallVector<Value> yielded(yield.getOperands());
  if (yielded.size() != task.getValues().size())
    return failure();
  rewriter.inlineBlockBefore(body, task);
  for (auto [result, value] : llvm::zip(task.getValues(), yielded))
    rewriter.replaceAllUsesWith(result, value);
  if (!task.getToken().use_empty())
    return failure();
  rewriter.eraseOp(yield);
  rewriter.eraseOp(task);
  return success();
}

struct InlineTask : OpRewritePattern<TaskOp> {
  using OpRewritePattern<TaskOp>::OpRewritePattern;

  LogicalResult matchAndRewrite(TaskOp op,
                                PatternRewriter &rewriter) const override {
    if (isa<ConcurrentOp>(op->getParentOp()))
      return failure();
    return inlineTaskAt(rewriter, op);
  }
};

struct InlineConcurrent : OpRewritePattern<ConcurrentOp> {
  using OpRewritePattern<ConcurrentOp>::OpRewritePattern;

  LogicalResult matchAndRewrite(ConcurrentOp op,
                                PatternRewriter &rewriter) const override {
    SmallVector<TaskOp> tasks;
    for (TaskOp task : op.getBody().front().getOps<TaskOp>())
      tasks.push_back(task);
    for (TaskOp task : tasks)
      if (failed(inlineTaskAt(rewriter, task)))
        return failure();

    Block *body = &op.getBody().front();
    auto yield = dyn_cast<YieldOp>(body->getTerminator());
    if (!yield)
      return failure();
    SmallVector<Value> results(yield.getOperands());
    rewriter.inlineBlockBefore(body, op);
    rewriter.replaceOp(op, results);
    rewriter.eraseOp(yield);
    return success();
  }
};

struct InlineOverlap : OpRewritePattern<OverlapOp> {
  using OpRewritePattern<OverlapOp>::OpRewritePattern;

  LogicalResult matchAndRewrite(OverlapOp op,
                                PatternRewriter &rewriter) const override {
    // Communicate first so side-effecting transfers complete before compute
    // reads the destination residency.
    if (failed(inlineRegionDropYield(rewriter, op.getCommunicate(), op)))
      return failure();
    Block *compute = &op.getCompute().front();
    auto yield = dyn_cast<YieldOp>(compute->getTerminator());
    if (!yield)
      return failure();
    SmallVector<Value> results(yield.getOperands());
    rewriter.inlineBlockBefore(compute, op);
    rewriter.replaceOp(op, results);
    rewriter.eraseOp(yield);
    return success();
  }
};

struct InlineStage : OpRewritePattern<StageOp> {
  using OpRewritePattern<StageOp>::OpRewritePattern;

  LogicalResult matchAndRewrite(StageOp op,
                                PatternRewriter &rewriter) const override {
    if (failed(inlineRegionDropYield(rewriter, op.getBody(), op)))
      return failure();
    rewriter.eraseOp(op);
    return success();
  }
};

struct InlinePipeline : OpRewritePattern<PipelineOp> {
  using OpRewritePattern<PipelineOp>::OpRewritePattern;

  LogicalResult matchAndRewrite(PipelineOp op,
                                PatternRewriter &rewriter) const override {
    if (failed(inlineRegionDropYield(rewriter, op.getBody(), op)))
      return failure();
    rewriter.eraseOp(op);
    return success();
  }
};

struct SequentializeS2C2Schedule
    : impl::SequentializeS2C2ScheduleBase<SequentializeS2C2Schedule> {
  using impl::SequentializeS2C2ScheduleBase<
      SequentializeS2C2Schedule>::SequentializeS2C2ScheduleBase;

  void runOnOperation() override {
    SmallVector<Operation *> syncOps;
    getOperation()->walk([&](Operation *op) {
      if (isa<WaitOp, BarrierOp>(op))
        syncOps.push_back(op);
    });
    for (Operation *op : llvm::reverse(syncOps))
      op->erase();

    RewritePatternSet patterns(&getContext());
    patterns.add<InlineTask, InlineConcurrent, InlineOverlap, InlineStage,
                 InlinePipeline>(&getContext());
    if (failed(applyPatternsGreedily(getOperation(), std::move(patterns))))
      signalPassFailure();
  }
};
} // namespace
} // namespace mlir::s2c2
