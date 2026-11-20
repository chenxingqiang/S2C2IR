//===- EventDependency.h - Tokens and textual order -------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_EXECUTIONMODEL_EVENTDEPENDENCY_H
#define S2C2_EXECUTIONMODEL_EVENTDEPENDENCY_H

#include "s2c2/ExecutionModel/HBGraph.h"

namespace mlir::s2c2::exec {

bool consumesToken(Operation *op, Value token);

/// A wait or barrier of `token` happens-before `read`.
bool eventVisible(Value token, Operation *read, const HBGraph &graph);

/// `a` is before `b` in one block, walking out to a common ancestor.
/// Nesting alone is not order: the ancestors must be distinct ops.
bool textuallyBefore(Operation *a, Operation *b);

} // namespace mlir::s2c2::exec

#endif // S2C2_EXECUTIONMODEL_EVENTDEPENDENCY_H
