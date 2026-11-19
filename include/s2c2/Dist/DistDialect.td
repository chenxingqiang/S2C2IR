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
  let summary = "S2C2 distribution dialect: logical shards and device coordinates.";
  let description = [{
    Logical placement is a global tensor cut into shards. A shard is
    replicated or sharded, with a partition axis, a tile shape, and an
    offset. The distribution verifier decides coverage, bounds, and
    overlap from those ranges alone.

    A device mesh names its axes and gives each rank a coordinate. A
    hardware topology is a line or a grid. `dist.place` checks that a
    logical distribution maps onto that topology. The mapping does not
    change shard ranges. A storage residency is not a device: two
    residencies in one space are not two coordinates.

    Collectives and routes are not operations. Nothing here lowers to a
    backend or a runtime.
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
