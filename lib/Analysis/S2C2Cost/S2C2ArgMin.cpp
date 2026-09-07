//===- S2C2ArgMin.cpp - List ArgMin_F and Pareto_F ---------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
// Set-valued listing over Enum_F = R ∩ F. Does not rewrite IR, pick a
// unique M*, treat π as a search variable, or redefine HB / Cost.
//
//   ArgMin_F  = argmin_{M ∈ Enum_F} Score_3(M).total
//   Pareto_F  = Pareto(Enum_F) over (T_HB, C_contention, C_capacity)
//
// Ties stay ties. ArgMin_F ≠ ArgMin_R ∩ F in general.
//
//===----------------------------------------------------------------------===//

#include "s2c2/S2C2Family.h"
#include "s2c2/S2C2Legality.h"
#include "s2c2/S2C2Passes.h"
#include "s2c2/S2C2Score3.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringMap.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/raw_ostream.h"

namespace mlir::s2c2 {
#define GEN_PASS_DEF_S2C2ARGMIN
#include "s2c2/S2C2Passes.h.inc"

namespace {
struct Member {
  StringRef sched;
  StringRef map;
  StringRef device;
  Score3 score;
};

struct S2C2ArgMin : impl::S2C2ArgMinBase<S2C2ArgMin> {
  using impl::S2C2ArgMinBase<S2C2ArgMin>::S2C2ArgMinBase;

  void runOnOperation() override {
    SmallVector<StringRef, 4> schedF, mapF, devF;
    Operation *mod = getOperation();
    if (failed(selectFamilyAxis(scheds, "argmin", "sched", familyF0Scheds(),
                                schedF, mod)) ||
        failed(selectFamilyAxis(maps, "argmin", "map", familyF0Maps(), mapF,
                                mod)) ||
        failed(selectFamilyAxis(devices, "argmin", "device", familyF0Devices(),
                                devF, mod))) {
      signalPassFailure();
      return;
    }

    for (auto func : getOperation().getOps<func::FuncOp>()) {
      if (func.getBody().empty())
        continue;

      llvm::StringMap<Score3> scoreByDevice;
      SmallVector<Member, 16> legal;
      for (StringRef s : schedF) {
        for (StringRef m : mapF) {
          for (StringRef d : devF) {
            if (!isLegalRealization(func, s, m, d))
              continue;
            auto it = scoreByDevice.find(d);
            if (it == scoreByDevice.end()) {
              Score3 scored;
              if (failed(computeScore3(func, d, scored))) {
                signalPassFailure();
                return;
              }
              it = scoreByDevice.insert({d, scored}).first;
            }
            legal.push_back(Member{s, m, d, it->second});
          }
        }
      }

      llvm::errs() << "s2c2-argmin func=" << func.getName()
                   << " enum=" << legal.size() << "\n";
      for (const Member &mem : legal)
        llvm::errs() << "s2c2-argmin func=" << func.getName()
                     << " sched=" << mem.sched << " map=" << mem.map
                     << " device=" << mem.device
                     << " critical_path=" << mem.score.criticalPath
                     << " contention=" << mem.score.contention
                     << " capacity=" << mem.score.capacity
                     << " total=" << mem.score.total << "\n";

      SmallVector<Member, 16> argmin;
      if (!legal.empty()) {
        int64_t best = legal.front().score.total;
        for (const Member &mem : legal)
          if (mem.score.total < best)
            best = mem.score.total;
        for (const Member &mem : legal)
          if (mem.score.total == best)
            argmin.push_back(mem);
      }
      llvm::errs() << "s2c2-argmin func=" << func.getName()
                   << " argmin count=" << argmin.size() << "\n";
      for (const Member &mem : argmin)
        llvm::errs() << "s2c2-argmin func=" << func.getName()
                     << " argmin sched=" << mem.sched << " map=" << mem.map
                     << " device=" << mem.device << " total=" << mem.score.total
                     << "\n";

      SmallVector<Member, 16> pareto;
      for (const Member &mem : legal) {
        bool dominated = false;
        for (const Member &other : legal) {
          if (strictlyDominates(other.score, mem.score)) {
            dominated = true;
            break;
          }
        }
        if (!dominated)
          pareto.push_back(mem);
      }
      llvm::errs() << "s2c2-argmin func=" << func.getName()
                   << " pareto count=" << pareto.size() << "\n";
      for (const Member &mem : pareto)
        llvm::errs() << "s2c2-argmin func=" << func.getName()
                     << " pareto sched=" << mem.sched << " map=" << mem.map
                     << " device=" << mem.device
                     << " critical_path=" << mem.score.criticalPath
                     << " contention=" << mem.score.contention
                     << " capacity=" << mem.score.capacity << "\n";
    }
  }
};
} // namespace
} // namespace mlir::s2c2
