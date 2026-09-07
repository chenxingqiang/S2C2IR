//===- S2C2CostCP.cpp - Critical-path cost score (v0.3) ---------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// Score-only print wrapper over shared computeScore3.
// Does not rewrite IR or redefine happens-before.
// Does not change --s2c2-cost or --s2c2-cost-hb.
//
//===----------------------------------------------------------------------===//

#include "s2c2/S2C2Passes.h"
#include "s2c2/S2C2Score3.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "llvm/Support/raw_ostream.h"

namespace mlir::s2c2 {
#define GEN_PASS_DEF_S2C2COSTCP
#include "s2c2/S2C2Passes.h.inc"

namespace {
struct S2C2CostCP : impl::S2C2CostCPBase<S2C2CostCP> {
  using impl::S2C2CostCPBase<S2C2CostCP>::S2C2CostCPBase;

  void runOnOperation() override {
    if (!isKnownScore3Device(device)) {
      getOperation()->emitError("unknown cost device '")
          << device << "'; expected cpu, gpu, npu, or cim";
      signalPassFailure();
      return;
    }
    for (auto func : getOperation().getOps<func::FuncOp>()) {
      if (func.getBody().empty())
        continue;
      Score3 s;
      if (failed(computeScore3(func, device, s))) {
        signalPassFailure();
        return;
      }
      llvm::errs() << "s2c2-cost-cp device=" << device
                   << " func=" << func.getName()
                   << " critical_path=" << s.criticalPath
                   << " contention=" << s.contention
                   << " capacity=" << s.capacity << " total=" << s.total
                   << "\n";
    }
  }
};
} // namespace
} // namespace mlir::s2c2
