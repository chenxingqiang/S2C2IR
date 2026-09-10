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
    `scf.for` / `scf.if` that carry `!stor.buffer` are structurally
    retargeted to memref (Phase 3I loop pipeline).

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
    "mlir::bufferization::BufferizationDialect",
    "mlir::scf::SCFDialect"
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
    "mlir::bufferization::BufferizationDialect",
    "mlir::scf::SCFDialect"
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
    "mlir::bufferization::BufferizationDialect",
    "mlir::scf::SCFDialect"
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
      Nxt = first(Best) on Frontier (scalar total; default)
            or first(Pareto(Frontier)) when nxt=pareto (v0.4.11)

    Does not rewrite IR, pick a unique M* as the output set, or
    redefine HB / Cost / π. Default `restart=true` restarts until
    Accepted = X (Complete). `restart=false` is the v0.4.10
    witness: stop at the first LocalStop and emit ArgMin(Accepted),
    which is not ArgMin_F when the first Hamming-1 component is a
    proper subset of X. A segment LocalStop is printed when
    Frontier is empty and Unused is still nonempty.

    `nxt=pareto` changes only Nxt. N / S / Rst / Acc stay as in
    v0.4.9. Not ArgMin-then-filter.

    `verify=true` (v0.4.12) asserts State invariants after Install
    and Acc. It is not a third Nxt.

    Same F flags as `--s2c2-enumerate`. Empty = F_0.
    This is not `--s2c2-search` and not beam / rewrite.
  }];
  let options = [
    Option<"scheds", "scheds", "std::string", /*default=*/"\"\"",
           "Comma-separated sched labels; empty = F_0">,
    Option<"maps", "maps", "std::string", /*default=*/"\"\"",
           "Comma-separated space-map labels; empty = F_0">,
    Option<"devices", "devices", "std::string", /*default=*/"\"\"",
           "Comma-separated device labels; empty = F_0">,
    Option<"restart", "restart", "bool", /*default=*/"true",
           "If false, stop at first LocalStop and emit ArgMin(Accepted)">,
    Option<"nxt", "nxt", "std::string", /*default=*/"\"scalar\"",
           "Next inhabitant: scalar (first(Best)) or pareto">,
    Option<"verify", "verify", "bool", /*default=*/"false",
           "Assert State invariants (v0.4.12); not a new algorithm">
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

def S2C2CapabilityQuery : Pass<"s2c2-capability-query", "::mlir::ModuleOp"> {
  let summary = "Query CapabilityRecord cells for concurrent pairs";
  let description = [{
    Phase 3A. Reads a CapabilityProfile (builtin `rtx4090` / `npu-demo`
    or a JSONL catalog) and prints one JSON object per queried pair.
    Does not rewrite IR, change happens-before, or score Cost.

    MVP pairs: C||HtoD, C||DtoH, HtoD||DtoH, C||C, C_silu||C_gemm.
    Optional `producer` / `consumer` query the catalog without IR.
    Walking `sched.concurrent` (2 tasks) and `sched.overlap` prints
    the same JSON for each classified pair, including `applicable`.
    A pair may have several `size_range` records; lookup uses the
    static payload. `arm_specific` / `inferred` evidence is queryable
    and is not a global compiler rule.
  }];
  let options = [
    Option<"device", "device", "std::string", /*default=*/"\"rtx4090\"",
           "Capability device id: rtx4090 or npu-demo">,
    Option<"profilePath", "profile", "std::string", /*default=*/"\"\"",
           "Optional CapabilityRecord JSONL catalog">,
    Option<"producer", "producer", "std::string", /*default=*/"\"\"",
           "Catalog query producer (comp.silu, comm.htod, ... )">,
    Option<"consumer", "consumer", "std::string", /*default=*/"\"\"",
           "Catalog query consumer">
  ];
}

def S2C2CapabilitySchedule : Pass<"s2c2-capability-schedule", "::mlir::ModuleOp"> {
  let summary = "Select a legal schedule from a CapabilityProfile";
  let description = [{
    Phase 3A CapabilityFilter. Same S²C² IR + different capability
    profiles → different legal realizations. Does not invent semantic
    dependency and does not rank by Cost.

      pair_relation = parallel | mixed | underdetermined  → keep concurrent
      pair_relation = serial AND applicable=yes
                      AND rewrite_license != no → unbundle 2-task
                               concurrent into parent IR order
      serial but arm_specific / inferred / unknown / size mismatch
                               → keep (evidence is not a global rule)
      serial size-band with rewrite_license=no in note
                               → keep (measured band, not a rewrite yet)

    Serializing concurrent siblings is a valid realization, not a new
    `sched.serial` op and not a sibling `sched.wait`. Pipeline
    StageOrder is never broken. After this pass, `--check-s2c2-execution`
    must still succeed: HB_before ⊆ HB_after (parent PO may add edges).
  }];
  let dependentDialects = [
    "mlir::s2c2::sched::ScheduleDialect",
    "mlir::s2c2::comp::ComputeDialect",
    "mlir::s2c2::comm::CommDialect",
    "mlir::s2c2::stor::StorageDialect"
  ];
  let options = [
    Option<"device", "device", "std::string", /*default=*/"\"rtx4090\"",
           "Capability device id: rtx4090 or npu-demo">,
    Option<"profilePath", "profile", "std::string", /*default=*/"\"\"",
           "Optional CapabilityRecord JSONL catalog">
  ];
}

def S2C2EvidenceBoundedSchedule : Pass<"s2c2-evidence-bounded-schedule", "::mlir::ModuleOp"> {
  let summary = "Profile + evidence licensed concurrent→serial rewrite";
  let description = [{
    Phase 3D compiler entry. Loads a named compiler profile
    (`rtx4090`, `910B`, `unknown`) or a compiler-profile JSON file,
    queries evidence, and applies the generic licensed
    concurrent→serial rewrite. Does not invent semantic dependency,
    rank by Cost, or read benchmark logs.

      --profile=rtx4090  → builtin 4090 evidence
      --profile=910B     → overlay projection (not #69 catalog)
      --profile=unknown  → empty evidence, preserve every concurrent

    Optional `--evidence=` JSONL overrides the profile catalog.
    `--s2c2-capability-schedule=profile=<jsonl>` is unchanged.
    After this pass, `--check-s2c2-execution` must still succeed.
    Walks every 2-task `sched.concurrent` as a storage-aware
    workload candidate. Prints KEEP (storage/communication overlap),
    FLATTEN (licensed compute contention), or PRESERVE (no evidence).
    Also walks `stor.materialize` / `stor.transfer` and prints a
    hierarchy plan: MATERIALIZE / PREFETCH / TRANSFER /
    KEEP_RESIDENCY / PRESERVE. Inferred overlap authorizes PREFETCH
    only; it does not flatten C||Storage. KEEP_RESIDENCY reuse
    applies only when a dominating, unmutated, same-type live
    replica is proven, including a prologue replica that dominates
    an enclosing `scf.for` and is not packed/deallocated in the
    loop. For-iter-args stay underdetermined. Prints `loop-pipeline`
    for each `scf.for` (report only; the loop is not rewritten).
    Optional `dump-schedule` writes the same decisions as JSON.
    Optional `measured-cost-table` is a JSONL of candidate-local
    `measured-storage-v1` records. Ranking does not retarget
    `default-3g` and does not rewrite the measured winner.
    Frozen `cost-v04` is unchanged. Does not flatten C||Storage.
    Optional `schedule-policy` names which ranking is the
    production selection (`default-3g` / `cost-v04` /
    `measured-storage-v1`). Policy cannot create legality or a
    rewrite license.     Optional `explain` prints the selection
    account. 5A–5D remain frozen. 5E is not opened.
    Optional `capacity` (`hbm:2`) prints F_capacity
    occupancy candidates. Optional `capacity-spec` is a
    `s2c2.capacity.v1` JSONL. Diagnostics only; rewrite=no.
    measured-capacity-v1 is not opened.
    Optional `dump-capacity-plan` writes the compiler-visible
    CapacityPlan JSON (`selected=none`). Not a rewrite license.
  }];
  let dependentDialects = [
    "mlir::s2c2::sched::ScheduleDialect",
    "mlir::s2c2::comp::ComputeDialect",
    "mlir::s2c2::comm::CommDialect",
    "mlir::s2c2::stor::StorageDialect",
    "mlir::scf::SCFDialect",
    "mlir::arith::ArithDialect"
  ];
  let options = [
    Option<"profileName", "profile", "std::string", /*default=*/"\"\"",
           "Named profile (rtx4090|910B|unknown) or compiler-profile JSON">,
    Option<"evidencePath", "evidence", "std::string", /*default=*/"\"\"",
           "Optional evidence JSONL override (not a benchmark log)">,
    Option<"dumpSchedule", "dump-schedule", "std::string", /*default=*/"\"\"",
           "Optional JSON dump of discovered candidates and decisions">,
    Option<"measuredCostTable", "measured-cost-table", "std::string",
           /*default=*/"\"\"",
           "Optional JSONL of measured-storage-v1 candidate records">,
    Option<"schedulePolicy", "schedule-policy", "std::string",
           /*default=*/"\"\"",
           "Selection policy: default-3g|cost-v04|measured-storage-v1">,
    Option<"explain", "explain", "bool", /*default=*/"false",
           "Print F, evidence, named-policy selection, rewrite=no">,
    Option<"capacityBudget", "capacity", "std::string", /*default=*/"\"\"",
           "Constrained space:tiles for F_capacity (hbm:2). Diagnostics only">,
    Option<"capacitySpec", "capacity-spec", "std::string", /*default=*/"\"\"",
           "Optional s2c2.capacity.v1 JSONL occupancy spec">,
    Option<"dumpCapacityPlan", "dump-capacity-plan", "std::string",
           /*default=*/"\"\"",
           "Write s2c2.capacity_plan.v1 JSON; selected=none">
  ];
}

def S2C2CapacityPlanQuery : Pass<"s2c2-capacity-plan-query", "::mlir::ModuleOp"> {
  let summary = "Query F_capacity as a consumer-visible CapacityPlan";
  let description = [{
    Phase 6C-D consumer query surface. Builds the same occupancy
    CapacityPlan as `--s2c2-evidence-bounded-schedule --capacity=...`,
    then prints `s2c2-capacity-plan-query` plus one
    `s2c2.capacity_plan.v1` JSON object. Does **not** apply a
    schedule, load Evidence DB, emit `s2c2-storage-capacity`, or
    issue a rewrite license. Default `selected` is `none`.
    Optional `capacity-policy=s0` selects first(F_capacity)
    (evict incoming at t*). Optional
    `capacity-policy=measured-capacity-v1` ranks enumerated
    F_capacity under scoped `s2c2.measured_capacity_cost.v1`
    records (`measured-capacity-table`). Matcher is
    profile + workload_class + candidate_identity, then
    measured=yes and correctness=1. Duplicate scoped
    identity is `duplicate-measured-identity`. Equal times
    pick the earliest F_capacity inhabitant. ArgMin is
    selection only; not a rewrite license. Prints the 6C-G
    capacity rewrite-license gate (`s2c2.capacity_license.v1`)
    with result still `no`: selected is not a license; EVICT
    requires a restore (`TRANSFER|REMATERIALIZE`). Truncated
    plans cannot be selected. Do not FileCheck microseconds.
    6C-B diagnostics stay frozen.
  }];
  let dependentDialects = [
    "mlir::s2c2::stor::StorageDialect",
    "mlir::s2c2::sched::ScheduleDialect"
  ];
  let options = [
    Option<"capacityBudget", "capacity", "std::string", /*default=*/"\"\"",
           "HBM occupancy budget (tiles). Same meaning as --capacity.">,
    Option<"capacitySpec", "capacity-spec", "std::string", /*default=*/"\"\"",
           "JSON capacity spec (same as --capacity-spec).">,
    Option<"dumpCapacityPlan", "dump-capacity-plan", "std::string",
           /*default=*/"\"\"",
           "Write s2c2.capacity_plan.v1 JSON to this path.">,
    Option<"capacityPolicy", "capacity-policy", "std::string",
           /*default=*/"\"\"",
           "Selection over F_capacity: none|s0|measured-capacity-v1.">,
    Option<"measuredCapacityTable", "measured-capacity-table", "std::string",
           /*default=*/"\"\"",
           "JSONL of s2c2.measured_capacity_cost.v1 (not a campaign log).">
  ];
}

def S2C2XForm : Pass<"s2c2-xform", "::mlir::ModuleOp"> {
  let summary = "Realization transformation T : P → P' (v0.5.1)";
  let description = [{
    Opens P ↦ P' as a program map, not a search inhabitant.

      T(P) ≠ ⊥  ⇒  HB(P') = HB(P)
      X' = Enum_F(P', D)   (rebuilt; old Enum_F discarded)

    kind=id: T_id(P) = P; HB equality by construction.
    kind=concurrent-reorder: swap the first HB-independent adjacent
    concurrent sibling pair; accept only if the rebuilt HB edge sets
    are equal. Does not apply Neighbor / Nxt, and is not
    --s2c2-search. Concurrent → Pipeline is not a kind.

    Same F flags as `--s2c2-enumerate`. Empty = F_0.
  }];
  let options = [
    Option<"kind", "kind", "std::string", /*default=*/"\"id\"",
           "Transform inhabitant: id or concurrent-reorder">,
    Option<"scheds", "scheds", "std::string", /*default=*/"\"\"",
           "Comma-separated sched labels; empty = F_0">,
    Option<"maps", "maps", "std::string", /*default=*/"\"\"",
           "Comma-separated space-map labels; empty = F_0">,
    Option<"devices", "devices", "std::string", /*default=*/"\"\"",
           "Comma-separated device labels; empty = F_0">
  ];
}

#endif // S2C2_PASSES
