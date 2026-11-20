//===- EventDependency.cpp - Tokens and textual order -----------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/ExecutionModel/EventDependency.h"

#include "s2c2/Comm/CommOps.h"
#include "s2c2/Schedule/ScheduleOps.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace mlir::s2c2;
using comm::BarrierOp;
using sched::WaitOp;

bool mlir::s2c2::exec::consumesToken(Operation *op, Value token) {
  return isa<WaitOp, BarrierOp>(op) && llvm::is_contained(op->getOperands(), token);
}

bool mlir::s2c2::exec::eventVisible(Value token, Operation *read,
                                   const HBGraph &graph) {
  for (OpOperand &use : token.getUses()) {
    Operation *user = use.getOwner();
    if (consumesToken(user, token) && graph.reaches(user, read))
      return true;
  }
  return false;
}

namespace {

int depthOf(Operation *op) {
  int depth = 0;
  for (Operation *parent = op->getParentOp(); parent;
       parent = parent->getParentOp())
    ++depth;
  return depth;
}

} // namespace

bool mlir::s2c2::exec::textuallyBefore(Operation *a, Operation *b) {
  if (!a || !b || a == b)
    return false;
  while (depthOf(a) > depthOf(b))
    a = a->getParentOp();
  while (depthOf(b) > depthOf(a))
    b = b->getParentOp();
  if (!a || !b || a == b)
    return false;
  while (a->getBlock() != b->getBlock()) {
    a = a->getParentOp();
    b = b->getParentOp();
    if (!a || !b)
      return false;
  }
  return a->isBeforeInBlock(b);
}
