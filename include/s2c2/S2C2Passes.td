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

def ConvertS2C2PipelineToAsync : Pass<"convert-s2c2-pipeline-to-async", "::mlir::ModuleOp"> {
  let summary = "HB-preserving v0.1 sched.pipeline → chained async.execute";
  let description = [{
    Phase 2B pipeline slice. Acceptance: **StageOrder is preserved**,
    not "the pipeline runs in parallel".

    Each stage becomes `async.execute`; the parent awaits that token
    before the next stage (and awaits the last stage as pipeline
    completion). Does not explode stages as unordered sibling executes.
    Does not add iteration IR or SoftPipe.
  }];
  let dependentDialects = ["mlir::async::AsyncDialect"];
}

def CheckS2C2Execution : Pass<"check-s2c2-execution", "::mlir::ModuleOp"> {
  let summary = "MustProve oracle for S2C2 happens-before and validity";
  let description = [{
    Phase 2B semantic tests (E1–E8). Builds HB = TC(PO ∪ SW) over
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

def S2C2Cost : Pass<"s2c2-cost", "::mlir::ModuleOp"> {
  let summary = "Score S2C2 IR against a device capability table";
  let description = [{
    v0.1 cost / resource model. Score-only; does not rewrite IR and does
    not redefine happens-before.

      Cost = C_compute + C_storage + C_communication + C_synchronization
             - C_overlap

    `C_storage` is bytes of a new residency (`materialize` / `alloc` /
    `transfer` dest) scored as ticks with coefficient 1.
    `C_overlap` is an upper-bound credit when the IR has unordered
    siblings (`sched.concurrent` / `sched.overlap`) **and** the device
    `canOverlap`. Pipeline stages stay sequential (StageOrder).

    Device profiles (`cpu`, `gpu`, `npu`, `cim`) are capability tables,
    not CUDA / NPU ISAs. Frozen v0.1; HB-aware scoring is
    `--s2c2-cost-hb`.
  }];
  let options = [
    Option<"device", "device", "std::string", /*default=*/"\"cpu\"",
           "Capability profile: cpu, gpu, npu, or cim">
  ];
}

def S2C2CostHB : Pass<"s2c2-cost-hb", "::mlir::ModuleOp"> {
  let summary = "HB-aware cost score (Cost Model v0.2)";
  let description = [{
    Score-only. Does not rewrite IR and does not redefine happens-before.

    Overlap credit requires OverlapCandidate(A, B):
      A ↛HB B ∧ B ↛HB A
      and OverlapCapability(kind(A), kind(B)).

    Does not change `--s2c2-cost` (v0.1 syntax heuristic). Frozen v0.2;
    critical-path scoring is `--s2c2-cost-cp`.
  }];
  let options = [
    Option<"device", "device", "std::string", /*default=*/"\"cpu\"",
           "Capability profile: cpu, gpu, npu, or cim">
  ];
}

def S2C2Enumerate : Pass<"s2c2-enumerate", "::mlir::ModuleOp"> {
  let summary = "List Enum_F = R(P, D) ∩ F (Realization Enumerator)";
  let description = [{
    Listing only. Does not rewrite IR, pick M*, score, or redefine HB.

      Output(M) = 1  iff  M ∈ R(P, D) ∩ F

    F is a declared finite family (default F_0). Completeness is inside
    F, not Enum = R. Does not apply ArgMin / Pareto / Search.
    π is not an enumerated component.

    Default F_0:

      scheds  = cpu-seq,gpu-async,npu-staged-dma
      maps    = default,t5
      devices = cpu,gpu,npu,cim

    `t5` is the T5 witness ssd=100,dram=2,hbm=9. Empty option fields
    use F_0. Requested labels are filtered to F_0 order.
    Because this pass does not rewrite P, HB_M = HB_source for every
    emitted M. IsLegal is the shared capability oracle
    (`isLegalRealization`), not F-membership. Illegal members of F
    are skipped.
  }];
  let options = [
    Option<"scheds", "scheds", "std::string", /*default=*/"\"\"",
           "Comma-separated sched labels; empty = F_0">,
    Option<"maps", "maps", "std::string", /*default=*/"\"\"",
           "Comma-separated space-map labels; empty = F_0">,
    Option<"devices", "devices", "std::string", /*default=*/"\"\"",
           "Comma-separated device labels; empty = F_0">
  ];
}

def S2C2ArgMin : Pass<"s2c2-argmin", "::mlir::ModuleOp"> {
  let summary = "List ArgMin_F and Pareto_F over Enum_F = R ∩ F";
  let description = [{
    Set-valued listing. Does not rewrite IR, pick a unique M*, or
    redefine HB / Cost / π.

      ArgMin_F  = argmin_{M ∈ Enum_F} Score_3(M).total
      Pareto_F  = Pareto(Enum_F) over (T_HB, C_contention, C_capacity)

    Enum_F is built with the shared IsLegal oracle and F_0 family
    helpers (same flags as `--s2c2-enumerate`). Score_3 is the frozen
    v0.3 CanonicalRealizationCost (shared `computeScore3`). Ties stay
    ties: ArgMin is a set. `total` is not a fourth Pareto objective.
    π is not printed.

    Empty option fields use F_0. Requested labels are filtered to F_0
    order. Because this pass does not rewrite P, HB_M = HB_source.
  }];
  let options = [
    Option<"scheds", "scheds", "std::string", /*default=*/"\"\"",
           "Comma-separated sched labels; empty = F_0">,
    Option<"maps", "maps", "std::string", /*default=*/"\"\"",
           "Comma-separated space-map labels; empty = F_0">,
    Option<"devices", "devices", "std::string", /*default=*/"\"\"",
           "Comma-separated device labels; empty = F_0">
  ];
}

def S2C2Walk : Pass<"s2c2-walk", "::mlir::ModuleOp"> {
  let summary = "Hamming-1 inhabitant of A (v0.4.9)";
  let description = [{
    First executable inhabitant of frozen A = (N, S, Rst, Nxt, Acc):

      N   = N_1
      S   = StartFirst
      Rst = StartUnused
      Nxt = first(Best) on Frontier (scalar total)

    Does not rewrite IR, pick a unique M* as the output set, or
    redefine HB / Cost / π. Restarts until Accepted = X (Complete).
    A segment LocalStop is printed when Frontier is empty and
    Unused is still nonempty. Output ArgMin is the set over
    Accepted; after Complete it equals ArgMin_F.

    Same F flags as `--s2c2-enumerate`. Empty = F_0.
    This is not `--s2c2-search` and not beam / Pareto / rewrite.
  }];
  let options = [
    Option<"scheds", "scheds", "std::string", /*default=*/"\"\"",
           "Comma-separated sched labels; empty = F_0">,
    Option<"maps", "maps", "std::string", /*default=*/"\"\"",
           "Comma-separated space-map labels; empty = F_0">,
    Option<"devices", "devices", "std::string", /*default=*/"\"\"",
           "Comma-separated device labels; empty = F_0">
  ];
}

def S2C2CostCP : Pass<"s2c2-cost-cp", "::mlir::ModuleOp"> {
  let summary = "Critical-path cost score (Cost Model v0.3)";
  let description = [{
    Score-only. Does not rewrite IR and does not redefine happens-before.

      Cost = T_critical_path(HB) + C_contention + C_capacity

    `C_contention` is T_full − T_HB after adding score-only
    serialization edges for HB-unordered, resource-incompatible pairs
    (IR order). `C_capacity` is the v0.2 storage occupancy term.
    Does not change `--s2c2-cost` or `--s2c2-cost-hb`.
  }];
  let options = [
    Option<"device", "device", "std::string", /*default=*/"\"cpu\"",
           "Capability profile: cpu, gpu, npu, or cim">
  ];
}

#endif // S2C2_PASSES
