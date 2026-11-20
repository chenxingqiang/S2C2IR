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

#include "mlir/IR/Value.h"
#include "llvm/ADT/SmallVector.h"

namespace mlir::s2c2::exec {

bool isV0Collective(Operation *op);

/// True when `value` is the collective result or a task/concurrent yield of it.
bool isCollectiveImage(Value value, Operation *collective);

/// One rank's contribution to one collective callsite.
struct CollectiveParticipant {
  Operation *collective = nullptr;
  Operation *input = nullptr;
  int64_t rank = -1;
  Value inputObject;
  Value resultObject;
  SmallVector<Operation *, 2> resultPacks;
};

/// One matched call. The participant key is (mesh, callsite, rank).
/// Kind is not part of the key: two all-reduces on one mesh are two instances.
struct CollectiveInstance {
  StringRef mesh;
  unsigned callsite = 0;
  StringRef kind;
  SmallVector<CollectiveParticipant, 4> participants;
};

struct CollectiveMatch {
  SmallVector<CollectiveInstance, 4> instances;
  Operation *faultOp = nullptr;
  const char *message = nullptr;
};

/// Align each mesh's per-rank collective sequence by callsite. A callsite is
/// one instance only when every mesh rank contributes, the inputs are that
/// rank's local residency of one logical object, and the kind, signature, and
/// result object agree. Call-order permutations are not repaired.
CollectiveMatch matchCollectiveInstances(func::FuncOp func);

/// C_r^in → C_complete_r → C_r^out, plus cross-rank edges inside one
/// matched instance. Instances on the same mesh do not share those edges.
void addCollectiveDependencies(func::FuncOp func, HBGraph &graph);

/// Rank program order plus per-instance collective dependencies. This is HB_D.
void buildHbD(func::FuncOp func, HBGraph &graph);

} // namespace mlir::s2c2::exec

#endif // S2C2_EXECUTIONMODEL_COLLECTIVEDEPENDENCY_H
