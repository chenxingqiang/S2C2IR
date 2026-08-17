//===- StorageTypes.td - S²C² Storage types --------------*- tablegen -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_STORAGE_TYPES
#define S2C2_STORAGE_TYPES

include "s2c2/Storage/StorageDialect.td"
include "mlir/IR/AttrTypeBase.td"
include "mlir/IR/EnumAttr.td"

def Stor_Space : I32EnumAttr<"Space", "S2C2 storage space", [
    I32EnumAttrCase<"Register", 0, "register">,
    I32EnumAttrCase<"SRAM", 1, "sram">,
    I32EnumAttrCase<"DRAM", 2, "dram">,
    I32EnumAttrCase<"HBM", 3, "hbm">,
    I32EnumAttrCase<"SSD", 4, "ssd">,
    I32EnumAttrCase<"CIM", 5, "cim">,
    I32EnumAttrCase<"Host", 6, "host">
  ]> {
  let cppNamespace = "::mlir::s2c2::stor";
  let genSpecializedAttr = 0;
}

def Stor_SpaceAttr : EnumAttr<Storage_Dialect, Stor_Space, "space"> {
  let assemblyFormat = "`<` $value `>`";
}

class Stor_Type<string name, string typeMnemonic, list<Trait> traits = []>
    : TypeDef<Storage_Dialect, name, traits> {
  let mnemonic = typeMnemonic;
}

def Stor_ObjectType : Stor_Type<"Object", "object"> {
  let summary = "Logical data identity (no placement, no allocation)";
  let description = [{
    `!stor.object<tensor<...>>` names a logical datum. Instance identity is
    the SSA value, not the type. Residencies of the same object are created
    with `stor.materialize` / `stor.transfer`.
  }];
  let parameters = (ins "Type":$payloadType);
  let assemblyFormat = "`<` $payloadType `>`";
  let genVerifyDecl = 1;
}

def Stor_BufferType : Stor_Type<"Buffer", "buffer"> {
  let summary = "Residency / handle of a tensor payload in a storage space";
  let description = [{
    `!stor.buffer<tensor<...>, space>` is a placed replica, not a logical
    identity. Pair it with a `!stor.object` SSA value via `stor.materialize`
    when alias / coherence analysis is required.

    The `space` parameter is a *logical* S²C² space. Integer memref memory
    spaces are a target mapping applied by `--convert-stor-to-memref`.
  }];
  let parameters = (ins
    "Type":$sourceType,
    "::mlir::s2c2::stor::Space":$space
  );
  let assemblyFormat = "`<` $sourceType `,` $space `>`";
  let genVerifyDecl = 1;
}

#endif // S2C2_STORAGE_TYPES
