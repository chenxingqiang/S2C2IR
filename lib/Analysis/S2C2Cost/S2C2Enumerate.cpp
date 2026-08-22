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

#include "s2c2/S2C2Legality.h"
#include "s2c2/S2C2Passes.h"

#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/ADT/StringSet.h"
#include "llvm/Support/raw_ostream.h"

#include <tuple>

namespace mlir::s2c2 {
#define GEN_PASS_DEF_S2C2ENUMERATE
#include "s2c2/S2C2Passes.h.inc"

namespace {
// F_0 declaration order. Deterministic product order, not a search rank.
static constexpr StringRef kSchedF0[] = {"cpu-seq", "gpu-async",
                                         "npu-staged-dma"};
static constexpr StringRef kMapsF0[] = {"default", "t5"};
static constexpr StringRef kDevsF0[] = {"cpu", "gpu", "npu", "cim"};

static void splitCSV(StringRef csv, SmallVectorImpl<StringRef> &out) {
  csv = csv.trim();
  if (csv.empty())
    return;
  while (!csv.empty()) {
    auto pair = csv.split(',');
    StringRef one = pair.first.trim();
    if (!one.empty())
      out.push_back(one);
    csv = pair.second;
  }
}

static LogicalResult
selectAxis(StringRef field, StringRef what, ArrayRef<StringRef> universe,
           SmallVectorImpl<StringRef> &out, Operation *reporter) {
  SmallVector<StringRef, 8> asked;
  splitCSV(field, asked);
  if (asked.empty()) {
    out.append(universe.begin(), universe.end());
    return success();
  }
  llvm::StringSet<> allow;
  for (StringRef u : universe)
    allow.insert(u);
  for (StringRef a : asked) {
    if (!allow.contains(a)) {
      reporter->emitError("unknown enumerate ")
          << what << " '" << a << "'; not in F_0";
      return failure();
    }
  }
  llvm::StringSet<> want;
  for (StringRef a : asked)
    want.insert(a);
  for (StringRef u : universe)
    if (want.contains(u))
      out.push_back(u);
  return success();
}

struct S2C2Enumerate : impl::S2C2EnumerateBase<S2C2Enumerate> {
  using impl::S2C2EnumerateBase<S2C2Enumerate>::S2C2EnumerateBase;

  void runOnOperation() override {
    SmallVector<StringRef, 4> schedF, mapF, devF;
    Operation *mod = getOperation();
    if (failed(selectAxis(scheds, "sched", kSchedF0, schedF, mod)) ||
        failed(selectAxis(maps, "map", kMapsF0, mapF, mod)) ||
        failed(selectAxis(devices, "device", kDevsF0, devF, mod))) {
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
