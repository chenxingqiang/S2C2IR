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

def Stor_SpaceAttr : EnumAttr<Storage_Dialect, Stor_Space, "space">;

class SpaceParameter
    : AttrOrTypeParameter<"::mlir::s2c2::stor::Space", "storage space"> {
  let parser = [{[&]() -> ::mlir::FailureOr<::mlir::s2c2::stor::Space> {
    ::llvm::StringRef mnemonic;
    if ($_parser.parseKeyword(&mnemonic))
      return ::mlir::failure();
    if (::std::optional<::mlir::s2c2::stor::Space> parsed =
            ::mlir::s2c2::stor::symbolizeSpace(mnemonic))
      return *parsed;
    return $_parser.emitError($_parser.getCurrentLocation())
           << "unknown storage space: " << mnemonic;
  }()}];
  let printer = [{$_printer << stringifySpace($_self)}];
}

class Stor_Type<string name, string typeMnemonic, list<Trait> traits = []>
    : TypeDef<Storage_Dialect, name, traits> {
  let mnemonic = typeMnemonic;
}

def Stor_BufferType : Stor_Type<"Buffer", "buffer"> {
  let summary = "Logical buffer placed in a storage space";
  let description = [{
    `!stor.buffer<tensor<...>, space>` pairs a ranked-tensor payload
    description with a storage space.
  }];
  let parameters = (ins
    "Type":$sourceType,
    SpaceParameter:$space
  );
  let assemblyFormat = "`<` $sourceType `,` $space `>`";
  let genVerifyDecl = 1;
}

#endif // S2C2_STORAGE_TYPES
