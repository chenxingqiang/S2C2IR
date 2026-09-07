//===- ScheduleOps.cpp - S2C2 Schedule ops ----------------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/Schedule/ScheduleOps.h"
#include "s2c2/Schedule/ScheduleDialect.h"
#include "llvm/ADT/STLExtras.h"

#include "s2c2/Schedule/ScheduleInterfaces.cpp.inc"

#define GET_OP_CLASSES
#include "s2c2/Schedule/ScheduleOps.cpp.inc"

using namespace mlir;
using namespace mlir::s2c2::sched;

static LogicalResult verifyYieldMatches(Operation *op, Region &region,
                                        ValueRange expected) {
  if (region.empty())
    return op->emitOpError("region must not be empty");
  auto yield = dyn_cast<YieldOp>(region.front().getTerminator());
  if (!yield)
    return op->emitOpError("region must terminate with sched.yield");
  if (yield.getNumOperands() != expected.size())
    return op->emitOpError("yield operands must match result types");
  for (auto [yielded, result] : llvm::zip(yield.getOperands(), expected)) {
    if (yielded.getType() != result.getType())
      return op->emitOpError("yield operand types must match result types");
  }
  return success();
}

LogicalResult TaskOp::verify() {
  return verifyYieldMatches(getOperation(), getBody(), getValues());
}

LogicalResult ConcurrentOp::verify() {
  if (failed(verifyYieldMatches(getOperation(), getBody(), getResults())))
    return failure();

  // v0.1: direct sched.task, or async.execute after token lowering.
  // Nested structured schedule (pipeline, overlap, concurrent) is deferred.
  for (Operation &child : getBody().front().without_terminator()) {
    if (!isa<TaskOp>(child) &&
        child.getName().getStringRef() != "async.execute")
      return emitOpError("body may only contain sched.task or async.execute "
                         "ops before the terminator");
  }
  return success();
}

LogicalResult OverlapOp::verify() {
  Region &compute = getCompute();
  if (compute.empty())
    return emitOpError("compute region must not be empty");

  auto yield = dyn_cast<YieldOp>(compute.front().getTerminator());
  if (!yield)
    return emitOpError("compute region must terminate with sched.yield");
  if (yield.getNumOperands() != getNumResults())
    return emitOpError("yield operands must match overlap results");
  for (auto [yielded, result] :
       llvm::zip(yield.getOperands(), getResults())) {
    if (yielded.getType() != result.getType())
      return emitOpError("yield operand types must match overlap results");
  }
  return success();
}

LogicalResult PipelineOp::verify() {
  // v0.1: valueless. StageResult / cross-stage SSA is a future feature.
  if (failed(verifyYieldMatches(getOperation(), getBody(), {})))
    return failure();
  for (Operation &child : getBody().front().without_terminator()) {
    if (!isa<StageOp>(child))
      return emitOpError(
          "body may only contain sched.stage ops before the terminator");
  }
  return success();
}

LogicalResult StageOp::verify() {
  return verifyYieldMatches(getOperation(), getBody(), {});
}
