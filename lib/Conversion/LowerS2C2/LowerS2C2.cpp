//===- LowerS2C2.cpp - Phase 2A lowering pipeline ---------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/S2C2Passes.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Bufferization/IR/Bufferization.h"
#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/Math/IR/Math.h"
#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/Pass/PassManager.h"

namespace mlir::s2c2 {
#define GEN_PASS_DEF_LOWERS2C2
#include "s2c2/S2C2Passes.h.inc"

namespace {
struct LowerS2C2 : impl::LowerS2C2Base<LowerS2C2> {
  using impl::LowerS2C2Base<LowerS2C2>::LowerS2C2Base;

  void runOnOperation() override {
    OpPassManager pm(getOperation()->getName());
    pm.addPass(createConvertCompToLinalg());
    pm.addPass(createSequentializeS2C2Schedule());
    ConvertStorToMemrefOptions storOpts;
    storOpts.spaceMap = spaceMap;
    pm.addPass(createConvertStorToMemref(storOpts));
    if (failed(runPipeline(pm, getOperation())))
      signalPassFailure();
  }
};
} // namespace
} // namespace mlir::s2c2
