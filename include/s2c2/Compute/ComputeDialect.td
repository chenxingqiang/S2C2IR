//===- ComputeDialect.td - S²C² Compute dialect ----------*- tablegen -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_COMPUTE_DIALECT
#define S2C2_COMPUTE_DIALECT

include "mlir/IR/OpBase.td"

def Compute_Dialect : Dialect {
  let name = "comp";
  let summary = "S2C2 compute dialect: what is computed and where it runs.";
  let description = [{
    High-level compute operations. These lower to `linalg` / `vector` / `scf`
    in later phases rather than duplicating those dialects.
  }];
  let cppNamespace = "::mlir::s2c2::comp";
  let useDefaultAttributePrinterParser = 1;
  let extraClassDeclaration = [{
    void registerAttributes();
  }];
}

class Comp_Op<string mnemonic, list<Trait> traits = []>
    : Op<Compute_Dialect, mnemonic, traits>;

#endif // S2C2_COMPUTE_DIALECT
