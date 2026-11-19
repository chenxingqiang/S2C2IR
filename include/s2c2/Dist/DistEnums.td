//===- DistEnums.td - S²C² distribution enums ------------*- tablegen -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_DIST_ENUMS
#define S2C2_DIST_ENUMS

include "s2c2/Dist/DistDialect.td"
include "mlir/IR/EnumAttr.td"

def Dist_Placement : I32EnumAttr<"Placement", "tensor placement", [
    I32EnumAttrCase<"Replicated", 0, "replicated">,
    I32EnumAttrCase<"Sharded", 1, "sharded">
  ]> {
  let cppNamespace = "::mlir::s2c2::dist";
  let genSpecializedAttr = 0;
}

def Dist_TopologyKind : I32EnumAttr<"TopologyKind", "hardware topology", [
    I32EnumAttrCase<"Line", 0, "line">,
    I32EnumAttrCase<"Grid", 1, "grid">
  ]> {
  let cppNamespace = "::mlir::s2c2::dist";
  let genSpecializedAttr = 0;
}

#endif // S2C2_DIST_ENUMS
