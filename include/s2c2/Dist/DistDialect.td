//===- DistDialect.td - S²C² distribution dialect --------*- tablegen -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_DIST_DIALECT
#define S2C2_DIST_DIALECT

include "mlir/IR/OpBase.td"

def Dist_Dialect : Dialect {
  let name = "dist";
  let summary = "S2C2 distribution dialect: how one tensor is partitioned.";
  let description = [{
    Semantic IR for one model tensor. A global tensor is associated with
    local tensors by shard and distribution values. Placement is either
    replicated (each local tensor is a full copy) or sharded (local tensors
    are tiles identified by a partition axis, a tile shape, and an offset).

    The verifier decides, from the IR alone, whether sharded ranges stay
    inside the global tensor, overlap, or leave a gap. Device mesh, rank
    placement, collectives, and routes are not operations of this dialect.
    Nothing here lowers to a backend or a runtime.
  }];
  let cppNamespace = "::mlir::s2c2::dist";
  let useDefaultTypePrinterParser = 1;
  let extraClassDeclaration = [{
    void registerTypes();
  }];
}

class Dist_Op<string mnemonic, list<Trait> traits = []>
    : Op<Dist_Dialect, mnemonic, traits>;

class Dist_Type<string name, string typeMnemonic, list<Trait> traits = []>
    : TypeDef<Dist_Dialect, name, traits> {
  let mnemonic = typeMnemonic;
}

#endif // S2C2_DIST_DIALECT
