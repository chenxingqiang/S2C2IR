//===- CommEnums.td - S²C² Communication enums -----------*- tablegen -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_COMM_ENUMS
#define S2C2_COMM_ENUMS

include "s2c2/Comm/CommDialect.td"
include "mlir/IR/EnumAttr.td"

def Comm_Kind : I32EnumAttr<"Kind", "communication kind", [
    I32EnumAttrCase<"P2P", 0, "p2p">,
    I32EnumAttrCase<"Broadcast", 1, "broadcast">,
    I32EnumAttrCase<"Reduce", 2, "reduce">
  ]> {
  let cppNamespace = "::mlir::s2c2::comm";
  let genSpecializedAttr = 0;
}
def Comm_KindAttr : EnumAttr<Comm_Dialect, Comm_Kind, "kind"> {
  let assemblyFormat = "`<` $value `>`";
}

def Comm_Engine : I32EnumAttr<"Engine", "transfer engine", [
    I32EnumAttrCase<"DMA", 0, "dma">,
    I32EnumAttrCase<"Copy", 1, "copy">,
    I32EnumAttrCase<"NoC", 2, "noc">
  ]> {
  let cppNamespace = "::mlir::s2c2::comm";
  let genSpecializedAttr = 0;
}
def Comm_EngineAttr : EnumAttr<Comm_Dialect, Comm_Engine, "engine"> {
  let assemblyFormat = "`<` $value `>`";
}

#endif // S2C2_COMM_ENUMS
