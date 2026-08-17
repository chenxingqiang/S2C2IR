//===- S2C2Passes.h - S2C2 passes -------------------------------*- C++ -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_S2C2PASSES_H
#define S2C2_S2C2PASSES_H

#include "mlir/Pass/Pass.h"
#include <memory>

namespace mlir {
namespace s2c2 {
#define GEN_PASS_DECL
#include "s2c2/S2C2Passes.h.inc"

#define GEN_PASS_REGISTRATION
#include "s2c2/S2C2Passes.h.inc"
} // namespace s2c2
} // namespace mlir

#endif // S2C2_S2C2PASSES_H
