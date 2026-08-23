//===- S2C2XForm.cpp - Realization transformation T : P → P' ----*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// v0.5.0: T_id(P) = P. HB(P') = HB(P) by construction. Rebuilds
// X' = Enum_F(P') with isLegalRealization. Not Search, not Nxt,
// not Concurrent → Pipeline, not --s2c2-search.
//
//===----------------------------------------------------------------------===//

#include "s2c2/S2C2Family.h"
#include "s2c2/S2C2Legality.h"
#include "s2c2/S2C2Passes.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/raw_ostream.h"

namespace mlir::s2c2 {
#define GEN_PASS_DEF_S2C2XFORM
#include "s2c2/S2C2Passes.h.inc"

namespace {
struct S2C2XForm : impl::S2C2XFormBase<S2C2XForm> {
  using impl::S2C2XFormBase<S2C2XForm>::S2C2XFormBase;

  void runOnOperation() override {
    Operation *mod = getOperation();
    if (kind != "id") {
      mod->emitError() << "s2c2-xform: kind must be id";
      signalPassFailure();
      return;
    }

    SmallVector<StringRef, 4> schedF, mapF, devF;
    if (failed(selectFamilyAxis(scheds, "xform", "sched", familyF0Scheds(),
                                schedF, mod)) ||
        failed(selectFamilyAxis(maps, "xform", "map", familyF0Maps(), mapF,
                                mod)) ||
        failed(selectFamilyAxis(devices, "xform", "device", familyF0Devices(),
                                devF, mod))) {
      signalPassFailure();
      return;
    }

    for (auto func : getOperation().getOps<func::FuncOp>()) {
      if (func.getBody().empty())
        continue;
      // T_id: P' = P. HB equality is construction, not a new HB engine.
      int rebuilt = 0;
      for (StringRef s : schedF)
        for (StringRef m : mapF)
          for (StringRef d : devF)
            if (isLegalRealization(func, s, m, d))
              ++rebuilt;
      llvm::errs() << "s2c2-xform func=" << func.getName() << " kind=id\n";
      llvm::errs() << "s2c2-xform func=" << func.getName() << " hb-eq=1\n";
      llvm::errs() << "s2c2-xform func=" << func.getName()
                   << " x-rebuilt count=" << rebuilt << "\n";
    }
  }
};
} // namespace
} // namespace mlir::s2c2
