//===- HBGraph.h - Shared happens-before graph -----------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// One program-order graph for the execution checker, HB_D, lowering, and
// realization transforms. Concurrent siblings do not order each other.

#ifndef S2C2_EXECUTIONMODEL_HBGRAPH_H
#define S2C2_EXECUTIONMODEL_HBGRAPH_H

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

namespace mlir::s2c2::exec {

struct HBGraph {
  void addEdge(Operation *from, Operation *to);
  void addEdges(ArrayRef<Operation *> froms, Operation *to);
  bool reaches(Operation *from, Operation *to) const;
  const llvm::DenseMap<Operation *, SmallVector<Operation *, 2>> &
  successors() const {
    return succ;
  }

private:
  llvm::DenseMap<Operation *, SmallVector<Operation *, 2>> succ;
};

/// Intra-device program order, including scf regions. Sibling tasks of one
/// `sched.concurrent` share the incoming frontier and do not order each other.
void buildProgramOrder(func::FuncOp func, HBGraph &graph);
void buildProgramOrder(ModuleOp module, HBGraph &graph);

/// Stable linear extension of `graph` restricted to `ops`. Ready nodes break
/// ties by their position in `ops`. Returns false when those edges cycle.
bool linearExtension(ArrayRef<Operation *> ops, const HBGraph &graph,
                     SmallVectorImpl<Operation *> &order);

} // namespace mlir::s2c2::exec

#endif // S2C2_EXECUTIONMODEL_HBGRAPH_H
