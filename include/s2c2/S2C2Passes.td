//===- S2C2Passes.td - S²C² passes -----------------------*- tablegen -*-===//
//
// This file is licensed under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef S2C2_PASSES
#define S2C2_PASSES

include "mlir/Pass/PassBase.td"

def ConvertStorToMemref : Pass<"convert-stor-to-memref", "::mlir::ModuleOp"> {
  let summary = "Convert S2C2 Storage ops to memref";
  let description = [{
    Lowers `stor.alloc` / `stor.materialize` / `stor.dealloc` to
    `memref.alloc` / `memref.dealloc`, and `stor.transfer` to alloc+copy.

    Logical S²C² spaces are mapped to integer memref memory spaces by a
    *target* map (not a hardware ABI). Default:

      register=0, sram=1, dram=2, hbm=3, ssd=4, cim=5, host=6

    Override with `space-map` (comma-separated `name=int` pairs; unspecified
    names keep the default), e.g. `space-map=hbm=9,ssd=100`.
  }];
  let dependentDialects = ["mlir::memref::MemRefDialect"];
  let options = [
    Option<"spaceMap", "space-map", "std::string", /*default=*/"\"\"",
           "Logical space to memref memory_space map (name=int pairs)">
  ];
}

def ExpandCompComposites : Pass<"expand-comp-composites", "::mlir::ModuleOp"> {
  let summary = "Expand composite compute ops using their decomposition contract";
  let description = [{
    Optional. Default pipelines keep `comp.gated_mlp` fused. Expansion:

      hidden = act(x @ Wgate) * (x @ Wup)
      y      = hidden @ Wdown
  }];
  let dependentDialects = ["mlir::s2c2::comp::ComputeDialect"];
}

#endif // S2C2_PASSES
