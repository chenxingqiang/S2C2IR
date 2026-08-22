//===- S2C2Enumerate.cpp - List Enum_F = R ∩ F -------------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// Listing only. Does not rewrite IR, pick M*, score, or redefine HB.
// Output(M) = 1 iff M ∈ R(P, D) ∩ F. No ArgMin / Pareto / Search.
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

#include <tuple>

namespace mlir::s2c2 {
#define GEN_PASS_DEF_S2C2ENUMERATE
#include "s2c2/S2C2Passes.h.inc"

namespace {
struct S2C2Enumerate : impl::S2C2EnumerateBase<S2C2Enumerate> {
  using impl::S2C2EnumerateBase<S2C2Enumerate>::S2C2EnumerateBase;

  void runOnOperation() override {
    SmallVector<StringRef, 4> schedF, mapF, devF;
    Operation *mod = getOperation();
    if (failed(selectFamilyAxis(scheds, "enumerate", "sched", familyF0Scheds(),
                                schedF, mod)) ||
        failed(selectFamilyAxis(maps, "enumerate", "map", familyF0Maps(), mapF,
                                mod)) ||
        failed(selectFamilyAxis(devices, "enumerate", "device",
                                familyF0Devices(), devF, mod))) {
      signalPassFailure();
      return;
    }

    for (auto func : getOperation().getOps<func::FuncOp>()) {
      if (func.getBody().empty())
        continue;
      // No rewrite ⇒ HB_M = HB_source. IsLegal is the capability oracle,
      // not F-membership.
      SmallVector<std::tuple<StringRef, StringRef, StringRef>, 16> legal;
      for (StringRef s : schedF)
        for (StringRef m : mapF)
          for (StringRef d : devF)
            if (isLegalRealization(func, s, m, d))
              legal.emplace_back(s, m, d);
      llvm::errs() << "s2c2-enumerate func=" << func.getName()
                   << " count=" << legal.size() << "\n";
      for (auto [s, m, d] : legal)
        llvm::errs() << "s2c2-enumerate func=" << func.getName()
                     << " sched=" << s << " map=" << m << " device=" << d
                     << "\n";
    }
  }
};
} // namespace
} // namespace mlir::s2c2
