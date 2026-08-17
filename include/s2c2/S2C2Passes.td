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
  let summary = "Convert S2C2 Storage alloc/dealloc to memref";
  let description = [{
    Lowers `stor.alloc` / `stor.dealloc` to `memref.alloc` / `memref.dealloc`.
    Storage spaces map to integer memref memory spaces:

      register=0, sram=1, dram=2, hbm=3, ssd=4, cim=5, host=6
  }];
  let dependentDialects = ["mlir::memref::MemRefDialect"];
}

#endif // S2C2_PASSES
