//===- CollectiveDependency.h - SPMD collective edges -----------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_EXECUTIONMODEL_COLLECTIVEDEPENDENCY_H
#define S2C2_EXECUTIONMODEL_COLLECTIVEDEPENDENCY_H

#include "s2c2/ExecutionModel/HBGraph.h"

namespace mlir::s2c2::exec {

bool isV0Collective(Operation *op);

/// True when `value` is the collective result or a task/concurrent yield of it.
bool isCollectiveImage(Value value, Operation *collective);

/// C_r^in → C_complete_r → C_r^out, plus cross-rank CDEP inside one
/// (grid, collective kind) group. Rank numbers are not edges. Meshes are
/// separate groups.
void addCollectiveDependencies(func::FuncOp func, HBGraph &graph);

/// Rank program order plus collective dependencies. This is HB_D.
void buildHbD(func::FuncOp func, HBGraph &graph);

} // namespace mlir::s2c2::exec

#endif // S2C2_EXECUTIONMODEL_COLLECTIVEDEPENDENCY_H
