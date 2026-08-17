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
  let summary = "Convert S2C2 storage (and remaining comm) to memref";
  let description = [{
    Lowers `stor.alloc` / `stor.materialize` / `stor.dealloc` to
    `memref.alloc` / `memref.dealloc`, `stor.transfer` / `comm.copy` /
    `comm.stream` to `memref.copy`, and `stor.pack` / `stor.unpack` to
    `bufferization.to_memref` / `bufferization.to_tensor`.

    Logical S²C² spaces are mapped to integer memref memory spaces by a
    *target* map (not a hardware ABI). Default:

      register=0, sram=1, dram=2, hbm=3, ssd=4, cim=5, host=6

    Override with `space-map` (comma-separated `name=int` pairs; unspecified
    names keep the default), e.g. `space-map=hbm=9,ssd=100`.
  }];
  let dependentDialects = [
    "mlir::memref::MemRefDialect",
    "mlir::bufferization::BufferizationDialect"
  ];
  let options = [
    Option<"spaceMap", "space-map", "std::string", /*default=*/"\"\"",
           "Logical space to memref memory_space map (name=int pairs)">
  ];
}

def ConvertCompToLinalg : Pass<"convert-comp-to-linalg", "::mlir::ModuleOp"> {
  let summary = "Convert S2C2 compute ops to linalg / tensor / math";
  let description = [{
    `comp.matmul` → `linalg.matmul` (zero-initialized dest).
    `comp.elemwise` add/mul → `linalg.add` / `linalg.mul`.
    Activations → `linalg.map` with `math` / `arith`.
    `comp.gated_mlp` is expanded with its decomposition contract then lowered.
  }];
  let dependentDialects = [
    "mlir::linalg::LinalgDialect",
    "mlir::tensor::TensorDialect",
    "mlir::arith::ArithDialect",
    "mlir::math::MathDialect"
  ];
}

def SequentializeS2C2Schedule : Pass<"sequentialize-s2c2-schedule", "::mlir::ModuleOp"> {
  let summary = "Inline S2C2 schedule regions in IR order and drop events";
  let description = [{
    Conservative sequential lowering: `sched.concurrent` / `sched.task` /
    `sched.overlap` / `sched.pipeline` / `sched.stage` are inlined.
    `sched.overlap` inlines the communicate region first, then compute.
    `!sched.token` waits and `comm.barrier` are erased (copies become
    blocking `memref.copy` in the memory conversion).
  }];
}

def ConvertCommToMemref : Pass<"convert-comm-to-memref", "::mlir::ModuleOp"> {
  let summary = "Convert S2C2 communication (and storage) to memref";
  let description = [{
    Same memory lowering as `--convert-stor-to-memref`, including
    `comm.copy` / `comm.stream` → `memref.copy`.
  }];
  let dependentDialects = [
    "mlir::memref::MemRefDialect",
    "mlir::bufferization::BufferizationDialect"
  ];
  let options = [
    Option<"spaceMap", "space-map", "std::string", /*default=*/"\"\"",
           "Logical space to memref memory_space map (name=int pairs)">
  ];
}

def LowerS2C2 : Pass<"s2c2-lower", "::mlir::ModuleOp"> {
  let summary = "Lower S2C2 to linalg / memref / bufferization";
  let description = [{
    Phase 2A pipeline:

      convert-comp-to-linalg
      sequentialize-s2c2-schedule
      convert-stor-to-memref (includes comm → memref.copy)

    Tokens are dropped (sequential). Async overlap is a later pass.
  }];
  let dependentDialects = [
    "mlir::linalg::LinalgDialect",
    "mlir::tensor::TensorDialect",
    "mlir::arith::ArithDialect",
    "mlir::math::MathDialect",
    "mlir::memref::MemRefDialect",
    "mlir::bufferization::BufferizationDialect"
  ];
  let options = [
    Option<"spaceMap", "space-map", "std::string", /*default=*/"\"\"",
           "Forwarded to storage/comm memref memory_space mapping">
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
