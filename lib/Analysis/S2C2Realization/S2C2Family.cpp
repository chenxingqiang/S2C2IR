//===- S2C2Family.cpp - Finite family F_0 axis helpers ----------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "s2c2/S2C2Family.h"

#include "mlir/IR/Operation.h"
#include "llvm/ADT/StringSet.h"

using llvm::ArrayRef;
using llvm::SmallVector;
using llvm::SmallVectorImpl;
using llvm::StringRef;

namespace mlir::s2c2 {

llvm::ArrayRef<llvm::StringRef> familyF0Scheds() {
  static constexpr StringRef kSchedF0[] = {"cpu-seq", "gpu-async",
                                           "npu-staged-dma"};
  return kSchedF0;
}

llvm::ArrayRef<llvm::StringRef> familyF0Maps() {
  static constexpr StringRef kMapsF0[] = {"default", "t5"};
  return kMapsF0;
}

llvm::ArrayRef<llvm::StringRef> familyF0Devices() {
  static constexpr StringRef kDevsF0[] = {"cpu", "gpu", "npu", "cim"};
  return kDevsF0;
}

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

LogicalResult selectFamilyAxis(StringRef field, StringRef passName,
                               StringRef what, ArrayRef<StringRef> universe,
                               SmallVectorImpl<StringRef> &out,
                               Operation *reporter) {
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
      reporter->emitError("unknown ")
          << passName << " " << what << " '" << a << "'; not in F_0";
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

} // namespace mlir::s2c2
