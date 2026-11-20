//===- ValidityAnalysis.h - Residency reads need a reaching write -*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_EXECUTIONMODEL_VALIDITYANALYSIS_H
#define S2C2_EXECUTIONMODEL_VALIDITYANALYSIS_H

#include "s2c2/ExecutionModel/HBGraph.h"

namespace mlir::s2c2::exec {

/// Emit the frozen undefined-read diagnostic. Returns true when any read
/// has no reaching pack, transfer, copy, or waited event. Yields alias the
/// inner buffer onto the parent result. `graph` is program order.
bool checkResidencyValidity(ModuleOp module, const HBGraph &graph);

} // namespace mlir::s2c2::exec

#endif // S2C2_EXECUTIONMODEL_VALIDITYANALYSIS_H
