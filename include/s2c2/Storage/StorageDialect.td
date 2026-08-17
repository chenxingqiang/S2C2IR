//===- StorageDialect.td - S²C² Storage dialect ----------*- tablegen -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_STORAGE_DIALECT
#define S2C2_STORAGE_DIALECT

include "mlir/IR/OpBase.td"

def Storage_Dialect : Dialect {
  let name = "stor";
  let summary = "S2C2 storage dialect: logical objects and placed residencies.";
  let description = [{
    Distinguishes logical data identity (`!stor.object`) from placed
    residencies (`!stor.buffer<tensor<...>, space>`). Spaces are logical;
    target memory-space integers are a conversion mapping, not an ABI.
  }];
  let cppNamespace = "::mlir::s2c2::stor";
  let useDefaultTypePrinterParser = 1;
  let useDefaultAttributePrinterParser = 1;
  let extraClassDeclaration = [{
    void registerTypes();
    void registerAttributes();
  }];
}

class Stor_Op<string mnemonic, list<Trait> traits = []>
    : Op<Storage_Dialect, mnemonic, traits>;

#endif // S2C2_STORAGE_DIALECT
