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
    `comm.stream` to `memref.copy` (**Phase 2A blocking approximation**;
    not event-preserving comm lowering), and `stor.pack` / `stor.unpack`
    to `bufferization.to_memref` / `bufferization.to_tensor`.

    `stor.materialize` is allocation only (contents unspecified).
    `stor.transfer` / copy / stream establish valid destination contents.

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
    Correctness realization, not the compute model:

    `comp.matmul` means `C = A @ B`; this pass may emit `linalg.fill(0)`
    plus `linalg.matmul` as a tensor-based dest.
    `comp.elemwise` is canonical math; add/mul → `linalg.add` /
    `linalg.mul`, activations → `linalg.map` with `math` / `arith`.
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
  let summary = "Blocking / legal total-order schedule baseline";
  let description = [{
    Semantic baseline, **not** a general schedule lowering:

      Sequential lowering ≠ S²C² semantics ≠ async lowering

    Makes async ops synchronous, then erases completion consumers
    (`sched.wait`, `comm.barrier`) and inlines regions. `sched.concurrent`
    children are inlined in IR order (one legal total order;
    `NoOrderingRequirement`). `sched.overlap` inlines communicate first,
    then compute. Phase 2B must not treat wait as unconditionally erasable.
  }];
}

def ConvertCommToMemref : Pass<"convert-comm-to-memref", "::mlir::ModuleOp"> {
  let summary = "Convert S2C2 communication (and storage) to memref";
  let description = [{
    Same **blocking** memory lowering as `--convert-stor-to-memref`.
    `comm.copy` / `comm.stream` → synchronous `memref.copy` is a Phase 2A
    approximation, not event-preserving communication lowering.
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
    Phase 2A sequential / blocking baseline (not async, not the semantic
    definition):

      convert-comp-to-linalg
      sequentialize-s2c2-schedule
      convert-stor-to-memref (blocking comm → memref.copy)

    Tokens are dropped because copies are synchronous. Event-preserving
    overlap is Phase 2B.
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

def ConvertS2C2TokenToAsync : Pass<"convert-s2c2-token-to-async", "::mlir::ModuleOp"> {
  let summary = "HB-preserving !sched.token → !async.token";
  let description = [{
    Phase 2B slice 1. Acceptance: **HB-preserving lowering**, not
    "async works".

    Token producers become `async.execute` (inner `comm.copy` is the
    transfer payload). `sched.wait` / `comm.barrier` become
    `async.await`. No wait ⇒ no await (does not invent sibling HB).

    Does not lower `sched.concurrent`, pipeline, or overlap.
  }];
  let dependentDialects = ["mlir::async::AsyncDialect"];
}

def ConvertS2C2ConcurrentToAsync : Pass<"convert-s2c2-concurrent-to-async", "::mlir::ModuleOp"> {
  let summary = "HB-preserving sched.concurrent → N × async.execute";
  let description = [{
    Phase 2B slice 2. Acceptance: **HB-preserving concurrent lowering**,
    not "async concurrent works".

    Direct `sched.task` / leftover `async.execute` children become
    sibling `async.execute` ops. Lexical sibling order does not insert
    `async.await`. A cross-sibling wait stays an await *inside* the
    consumer. Task-local SSA is remapped per child.

    Does not lower pipeline or overlap.
  }];
  let dependentDialects = ["mlir::async::AsyncDialect"];
}

def CheckS2C2Execution : Pass<"check-s2c2-execution", "::mlir::ModuleOp"> {
  let summary = "MustProve oracle for S2C2 happens-before and validity";
  let description = [{
    Phase 2B semantic tests (E1–E7). Builds HB = TC(PO ∪ SW) over
    observable actions. Concurrent sibling textual order is not PO.
    Async dest validity is visible only through wait of the transfer
    event or the enclosing task event.

    This is a MustProve checker, not a completeness claim
    (semantic validity ≠ static verifiability). It does not lower
    `!sched.token`.
  }];
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
