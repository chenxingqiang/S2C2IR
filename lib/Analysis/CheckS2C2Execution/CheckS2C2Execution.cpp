//===- CheckS2C2Execution.cpp - HB / validity oracle ------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// MustProve checker for Execution Semantics E1–E8. Not token lowering.
// The program-order graph and the residency check live in ExecutionModel.
// MeshSize 1 is that same single-device relation.

#include "s2c2/ExecutionModel/HBGraph.h"
#include "s2c2/ExecutionModel/ValidityAnalysis.h"
#include "s2c2/S2C2Passes.h"

#include "mlir/IR/BuiltinOps.h"

namespace mlir::s2c2 {
#define GEN_PASS_DEF_CHECKS2C2EXECUTION
#include "s2c2/S2C2Passes.h.inc"

namespace {
struct CheckS2C2Execution : impl::CheckS2C2ExecutionBase<CheckS2C2Execution> {
  using impl::CheckS2C2ExecutionBase<CheckS2C2Execution>::CheckS2C2ExecutionBase;

  void runOnOperation() override {
    exec::HBGraph graph;
    exec::buildProgramOrder(getOperation(), graph);
    if (exec::checkResidencyValidity(getOperation(), graph))
      signalPassFailure();
  }
};
} // namespace
} // namespace mlir::s2c2
