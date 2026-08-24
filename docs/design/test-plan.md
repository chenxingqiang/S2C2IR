# Test Plan

Executable tests live under `test/` and run via `check-s2c2` (llvm-lit + FileCheck).

## Storage

| ID | File | Checks |
| -- | ---- | ------ |
| S1 | `test/Storage/ops.mlir` | Round-trip `alloc`/`dealloc`/`pack`/`unpack` |
| S2 | `test/Storage/invalid.mlir` | Unpack payload type must match buffer source type |
| S3 | `test/Storage/ops.mlir` | `object` / `materialize` / `transfer` round-trip |
| S4 | `test/Storage/invalid.mlir` | Materialize / transfer payload must match |
| S5 | `test/Comm/invalid.mlir` | Stream requires the same logical object |

## Compute

| ID | File | Checks |
| -- | ---- | ------ |
| C1 | `test/Compute/ops.mlir` | Round-trip `matmul`, `elemwise`, `gated_mlp` |
| C2 | `test/Conversion/expand-comp-composites.mlir` | Optional fused-candidate expansion |

## Communication

| ID | File | Checks |
| -- | ---- | ------ |
| M1 | `test/Comm/ops.mlir` | Round-trip `copy`, `stream`, `barrier` |
| M2 | `test/Comm/invalid.mlir` | Stream src/dst payload types must match |
| M3 | `test/Comm/ops.mlir` | Object-backed stream; async `copy -> !sched.token` |

## Schedule

| ID | File | Checks |
| -- | ---- | ------ |
| H1 | `test/Schedule/ops.mlir` | Round-trip `wait`, `overlap`, `pipeline`, `stage` |
| H2 | `test/Schedule/ops.mlir` | `concurrent` + `task` with value + token results |
| H3 | `test/Schedule/invalid.mlir` | Task yield operands must match task values |
| H4 | `test/Schedule/invalid.mlir` | `concurrent` body may only contain `sched.task` or `async.execute` |
| H5 | `test/Schedule/invalid.mlir` | v0.1 `sched.stage` / `sched.pipeline` yield must be valueless |

## Conversion

| ID | File | Checks |
| -- | ---- | ------ |
| V1 | `test/Conversion/stor-to-memref.mlir` | Default map: `hbm` → `memref<..., 3>`; pack/unpack |
| V2 | `test/Conversion/stor-to-memref.mlir` | Override `space-map=hbm=9,ssd=100`; materialize/transfer |
| V3 | `test/Conversion/comp-to-linalg.mlir` | matmul / elemwise / gated_mlp → linalg |
| V4 | `test/Conversion/sequentialize-schedule.mlir` | overlap communicate-first; concurrent IR order |
| V5 | `test/Conversion/comm-to-memref.mlir` | stream/copy → memref.copy; wait erased |

## Integration

| ID | File | Checks |
| -- | ---- | ------ |
| I1 | `test/Integration/gated_mlp_ssd_stream.mlir` | Object identity, HBM replicas, concurrent gated MLP + stream |
| I2 | same file `--s2c2-lower` | Lowers to linalg + memref.copy + bufferization.to_tensor |

## Execution semantics (`--check-s2c2-execution`)

See [`execution-semantics.md`](execution-semantics.md) §13. Oracle only;
not token → async lowering.

| ID | File | Checks |
| -- | ---- | ------ |
| E1 | `test/Semantics/e1.mlir` | `materialize` then unpack, no write → undefined |
| E2 | `test/Semantics/e2.mlir` | `stream` + `wait` + unpack → dest valid |
| E3 | `test/Semantics/e3.mlir` | Concurrent stream ∥ unpack without wait → undefined |
| E4 | `test/Semantics/e4.mlir` | Wait producer task event → defined |
| E5 | `test/Semantics/e5.mlir` | Both sibling orders of event-free concurrent are legal |
| E6 | `test/Semantics/e6.mlir` | Pipeline `S1` write →HB `S2` read |
| E7 | `test/Semantics/e7.mlir` | T1-before-T2 textual order without event → undefined |
| E8 | `test/Semantics/e8.mlir` | Pipeline `S1` read then `S2` write → undefined (directed StageOrder) |

Pipeline contract: [`pipeline-semantics.md`](pipeline-semantics.md)
(v0.1 frozen). Lowering: chained await, not unordered executes.

## Composition (Token + Concurrent + Pipeline)

Frozen. This layer only checks the three constructs compose without
interference. Design: [`phase2b-composition.md`](phase2b-composition.md).

| ID | File | Checks |
| -- | ---- | ------ |
| X1 | `test/Semantics/compose-token-pipeline-concurrent.mlir` | Prefetch SW, S1→S2 StageOrder, concurrent siblings on distinct residencies: all reads defined |
| X1 | `test/Conversion/compose-token-pipeline-concurrent.mlir` | Prefetch await before S1; await S1 before S2; sibling executes inside S2 with `CHECK-NOT: async.await` between launches; join at stage completion |

## Token → async (HB-preserving slice)

| ID | File | Checks |
| -- | ---- | ------ |
| A2 | `test/Conversion/token-to-async-e2.mlir` | stream+wait → execute + await before unpack |
| A3 | `test/Conversion/token-to-async-e3.mlir` | no wait ⇒ no await (no invented HB) |
| A4 | `test/Conversion/token-to-async-e4.mlir` | wait(event(T1)) → await of T1 execute token |
| A5 | `test/Conversion/token-to-async-a5.mlir` | nested inner execute; PO before stream and after wait |
| A6 | `test/Conversion/token-to-async-a6.mlir` | task-local stream operands remapped into nested copy |
| A7 | `test/Conversion/token-to-async-a7.mlir` | no flatten when src/dst are defined inside the task |

## Concurrent → async (HB-preserving slice 2)

| ID | File | Checks |
| -- | ---- | ------ |
| C1 | `test/Conversion/concurrent-to-async-c1.mlir` | no-wait siblings: two executes, no await |
| C2 | `test/Conversion/concurrent-to-async-c2.mlir` | each sibling remaps its own task-local SSA |
| C3 | `test/Conversion/concurrent-to-async-c3.mlir` | consumer awaits producer token; parent awaits result value |

## Pipeline → async (v0.1 StageOrder)

| ID | File | Checks |
| -- | ---- | ------ |
| P1 | `test/Conversion/pipeline-to-async-p1.mlir` | await S1 (pack) before S2 unpack |
| P2 | `test/Conversion/pipeline-to-async-p2.mlir` | three stages, await between each execute |
| P3 | `test/Conversion/pipeline-to-async-p3.mlir` | stage-local SSA remapped; S2 awaits S1 |

Composition of the three (no new semantics): X1 in the Composition
section above.

## Capability / target mapping (v0.1)

Does not change Token / Concurrent / Pipeline. Design:
[`capability-mapping.md`](capability-mapping.md).

| ID | File | Checks |
| -- | ---- | ------ |
| T1 | `test/Conversion/capability-matrix.mlir` `--s2c2-lower` | cpu-seq: blocking `memref.copy`, no async/wait |
| T2 | same, three async passes | gpu-async / npu staged-DMA shape: prefetch SW, StageOrder, `CHECK-NOT: async.await` between S2 siblings |
| T5 | same `--s2c2-lower=space-map=...` | ssd/hbm integers from the target map |
| T5b | `@ssd_dram_hbm_hops` | SSD→DRAM→HBM Token chain |

## Cost / resource model (v0.1)

Score-only. Design: [`cost-resource-model.md`](cost-resource-model.md).

| ID | File | Checks |
| -- | ---- | ------ |
| K1 | `test/Analysis/s2c2-cost.mlir` | concurrent IR: CPU `overlap=0`, GPU `overlap>0` |
| K2 | same | sequential IR: `overlap=0` on CPU and GPU |
| K3 | same | pipeline stages: GPU `overlap=0` (StageOrder ≠ overlap) |
| K4 | same | `sched.wait` counts in `synchronization` |

## Cost Model v0.2 (HB-aware)

v0.1 stays frozen. Design:
[`cost-resource-model-v02.md`](cost-resource-model-v02.md).

| ID | File | Checks |
| -- | ---- | ------ |
| H1 | `test/Analysis/s2c2-cost-hb.mlir` | Compute∥IO, no HB: GPU overlap > 0 |
| H2 | same | sequential: overlap=0 |
| H3 | same | pipeline: GPU overlap=0 |
| H5 | same | wait sibling: GPU overlap=0 (HB removes the pair) |
| H5′ | same `--s2c2-cost` | frozen v0.1 still credits GPU overlap on that wait sibling |
| H6 | same | two IO streams: GPU overlap=0 (IO∥IO = 0) |

## Cost Model v0.3 (critical path)

v0.1 and v0.2 stay frozen. Design:
[`cost-resource-model-v03.md`](cost-resource-model-v03.md).

| ID | File | Checks |
| -- | ---- | ------ |
| C1 | `test/Analysis/s2c2-cost-cp.mlir` | Compute∥IO: GPU contention=0 |
| C2 | same | sequential: contention=0 |
| C3 | same | pipeline: StageOrder in T_HB, contention=0 |
| C5 | same | wait sibling: SW in T_HB, GPU contention=0 |
| C6 | same | two IO streams: GPU contention>0 |
| C7 | same | sibling `{compute; IO}` chains: v0.2 total is optimistic |
| C8 | same | Compute∥DMA∥IO: T_HB is max of three kinds |
| C9 | same | reverse-looking SW + unordered IO: canonical orientation keeps G_full a DAG |

## Realization Space (v0.4.0)

**Frozen.** Does not search. Design:
[`realization-space.md`](realization-space.md).

| ID | File | Checks |
| -- | ---- | ------ |
| R1 | `test/Conversion/capability-matrix.mlir` `--s2c2-lower` | cpu-seq ∈ R |
| R2 | same, async triple | gpu-async ∈ R; no sibling await |
| R3 | same `space-map` | space-map ∈ R |
| R4 | `test/Analysis/realization-space.mlir` | same P: Score_3(cpu)=136, Score_3(gpu)=128 |
| R5 | design claim in `realization-space.md` | Concurrent → Pipeline ∉ R (`HB_M ≠ HB_source`) |
| R6 | `test/Analysis/s2c2-cost-cp.mlir` C9 | π is canonical, not a search choice |

## Search / Pareto (v0.4.1)

**Frozen.** Design only. Reuses existing Score_3 numbers. Design:
[`search-pareto.md`](search-pareto.md). Fixture claims S1/S2 use
`D_test={cpu,gpu}`.

| ID | File | Checks |
| -- | ---- | ------ |
| S1 | `test/Analysis/realization-space.mlir` R4 | `D_test={cpu,gpu}`: every scalar minimum uses gpu (128 < 136) |
| S2 | `test/Analysis/s2c2-cost-cp.mlir` C6 / C9 | `D_test={cpu,gpu}`: equal totals ⇒ both minima |
| S3 | design claim | Concurrent → Pipeline ∉ domain |
| S4 | C9 | π is not a search axis |
| S5 | C1 | GPU weakly dominates CPU on Cost⃗; device-table fact |
| S6 | R1 / R2 | cpu-seq and gpu-async stay distinct M |

## Realization Enumerator (v0.4.2)

**Frozen.** Completeness is `R ∩ F`, not `R`. Design:
[`realization-enumerator.md`](realization-enumerator.md).

| ID | File | Checks |
| -- | ---- | ------ |
| N1 | design claim | `\|F_0\| = 3 × 2 × 4 = 24` |
| N2 | design claim | `Enum = R ∩ F`; no heuristic drop |
| N3 | R1 / R2 / R3 | existing witnesses ∈ Enum for their F |
| N4 | R5 | Concurrent → Pipeline ∉ F and ∉ Enum |
| N5 | C9 / R6 | `π` is not an enumerated component |
| N6 | S1 / S2 | `Dev_F = D_test={cpu,gpu}` |
| N7 | C6 | `Enum_F` keeps both equal-total members; `ArgMin_F` may keep both |
| N8 | design claim | `ArgMin_R ∩ F = ∅` ⇏ `ArgMin_F = ∅`; see enumerator §4 counterexample |

## Realization Enumerator listing (v0.4.3)

**Frozen.** `--s2c2-enumerate`. Design:
[`realization-enumerator-pass.md`](realization-enumerator-pass.md).
Contract: `Output = R ∩ F` via `isLegalRealization`. No ArgMin /
Search / rewrite.

| ID | File | Checks |
| -- | ---- | ------ |
| L1 | `test/Analysis/realization-enumerate.mlir` F0 | `count=8` = `|R ∩ F_0|`, legal T1/T2/T3 order |
| L2 | same | R1/R2/R3 labels present; no `sched=pipeline`, `pi=`, `argmin`, `total=` |
| L3 | same DTEST | `D_test={cpu,gpu}` ⇒ `count=4`; no npu/cim |
| L4 | same IR | module still has `sched.concurrent` |
| N9 | same F0 | illegal-in-F skipped (`npu-staged-dma`+`cim`, `gpu-async`+`cpu`, …) |
| N10 | same F0 | every legal member emitted |

## ArgMin_F / Pareto_F listing (v0.4.4)

**Frozen.** `--s2c2-argmin`. Design:
[`realization-argmin-pass.md`](realization-argmin-pass.md).
Contract: set-valued `ArgMin_F` / `Pareto_F` over `Enum_F`. Shared
`computeScore3`. No unique `M*`, rewrite, or `π`.

| ID | File | Checks |
| -- | ---- | ------ |
| A1 | `test/Analysis/s2c2-argmin.mlir` F0 | `enum=8`; frozen Score_3 per device |
| A2 | same F0 | `argmin count=4` (gpu+npu ties, both maps) |
| A3 | same F0 | `pareto count=4`; cpu/cim dominated; no `winner=` / `pi=` |
| A4 | same DTEST | `D_test={cpu,gpu}`: `argmin count=2`, both gpu-async |
| A5 | same IR | module still has `sched.concurrent` |
| A6 | same CP | `--s2c2-cost-cp` gpu total still 128 |

## Search Space / Neighbor / Legality (v0.4.5)

**Frozen.** No algorithm pass. Design:
[`search-space.md`](search-space.md). `Neighbor` generates in `F`;
`LegalNeighbor` accepts only `R ∩ F`.

| ID | File | Checks |
| -- | ---- | ------ |
| K1 | design claim | Search Space `X = Enum_F`, not `F` or all of `R` |
| K2 | design claim | `M' ∈ Neighbor(M) ⇏ M' ∈ R` |
| K3 | design claim | `LegalNeighbor = Neighbor ∩ Enum_F`; Accept ⇒ `R` |
| K4 | A1–A3 | `ArgMin_F` is batch optimization on `X` with implicit `N_all` |
| K5 | design claim | `N_1` Hamming-1 on `F_0` has size 6 |
| K6 | N9 / A2 | illegal neighbors discarded, not scored into `ArgMin_F` |
| K7 | S3 / N4 | Concurrent → Pipeline ∉ `LegalNeighbor` |
| K8 | design claim | no `--s2c2-search`; `π` is not a Neighbor axis |
| K9 | design claim | `M ∈ N_all(M)` and `M ∉ N_1(M)`; a path starts in `X` |
| K10 | design claim | rewrite `P ↦ P'` rebuilds `X(P', D; F)` |

## Search Algorithm Contract (v0.4.6)

**Frozen.** No `--s2c2-search`. Design:
[`search-algorithm-contract.md`](search-algorithm-contract.md).
`--s2c2-argmin` is the Complete / `N_all` witness.

| ID | File | Checks |
| -- | ---- | ------ |
| T1 | design claim | `State_walk.current ∈ X`; `π ∉ State` |
| T2 | design claim | `Checked ⊆ F`, `LegalChecked ⊆ X`; no re-Validate; illegal flips not scored |
| T3 | A6 | Cache fills on validated `M ∈ X` before Accept; keys are `device` |
| T4 | A2 | `WalkTieBreak` does not shrink `ArgMin_F` |
| T5 | design claim | `next = first(Best)` in F_0 order; `Best` is a set |
| T6 | A1–A3 | `Complete ⇒ Output = ArgMin_F / Pareto_F` |
| T7 | design claim | `LocalStop ⇏ Output = ArgMin_F` |
| T8 | design claim | walk order is Generate → Validate → [Score] → Select → Accept |
| T9 | design claim | `Scored ⇏ Accepted` and `Accepted ⊆ Scored` |

## StartPolicy / RestartPolicy (v0.4.7)

**Frozen.** No `--s2c2-search`. Design:
[`search-start-policy.md`](search-start-policy.md). Does not freeze
`StartFirst` or `StartBest` as *the* algorithm.

| ID | File | Checks |
| -- | ---- | ------ |
| U1 | design claim | `StartPolicy ∈ X`; `π` not an input |
| U2 | design claim | must not require `ArgMin_F` as an input |
| U3 | T1 | `Install(M)` is the only way to set `current` |
| U4 | design claim | `StartFirst` / `StartUnused` / `StartGiven` are kinds |
| U5 | design claim | `StartBest` reserved; not the v0.4.7 default |
| U6 | design claim | `RestartPolicy(Unused) ∈ Unused`; keep `Checked` / `Cache` |
| U7 | T6 / T7 | restarts to `Unused=∅` ⇒ Complete; one LocalStop ⇏ `ArgMin_F` |
| U8 | A1–A3 | `--s2c2-argmin` does not use `StartPolicy` |

## Algorithm object (v0.4.8)

**Frozen.** No inhabitant, no `--s2c2-search`. Design:
[`search-algorithm.md`](search-algorithm.md).

| ID | File | Checks |
| -- | ---- | ------ |
| V1 | design claim | `A = (N, S, Rst, Nxt, Acc)` |
| V2 | design claim | `Nxt ∈ LegalNeighbor ∪ {⊥}` |
| V3 | design claim | `Nxt = ⊥ ⇔ Frontier = ∅` |
| V4 | design claim | `Acc` only when `M = Nxt ≠ ⊥`; `current' = M` |
| V5 | U3 | `Install ≠ Acc`; start/restart still `Install` |
| V6 | T9 | invariants hold after `Install` and `Acc` |
| V7 | T7 | `⊥` is segment LocalStop, not Complete |
| V8 | design claim | no hill-climbing / beam chosen |

## Hamming-1 walk (v0.4.9)

**Executable.** `--s2c2-walk`. Design:
[`search-walk-n1.md`](search-walk-n1.md). Inhabitant
`N_1` / `StartFirst` / `StartUnused` / `first(Best)`.

| ID | File | Checks |
| -- | ---- | ------ |
| W1 | `test/Analysis/s2c2-walk.mlir` F0 | StartFirst = cpu-seq/default/cpu; N_1 steps as listed |
| W2 | same F0 | LocalStop then Restart unused; Complete accepted=8 |
| W3 | same F0 | after Complete, argmin count=4 matches `--s2c2-argmin` |
| W4 | same DTEST | LocalStop accepted=2 then restart gpu; Complete=4 |
| W5 | same IR | `sched.concurrent` unchanged |
| W6 | same | no `winner=`, no `pi=` |
| W7 | same F0 | `Nxt` is total: every decision is `step` or `localstop` (`F0-NEXT`); never error / undefined / outside `X` |

## Restart / Complete coverage (v0.4.10)

**Executable.** `--s2c2-walk=restart=false`. Design:
[`search-restart-complete.md`](search-restart-complete.md). Same
inhabitant as v0.4.9; `Rst` withheld after the first LocalStop.

| ID | File | Checks |
| -- | ---- | ------ |
| R1 | `test/Analysis/s2c2-walk.mlir` STOP | one segment: localstop accepted=4; argmin count=2 total=129 (both cim) |
| R2 | same STOP | no `complete`, no `restart`, no gpu/npu in the LocalStop output |
| R3 | same AMIN | `--s2c2-argmin` still count=4 total=128 |
| R4 | R1 vs R3 | `ArgMin(Accepted)=129` ≠ `ArgMin_F=128` |
| R5 | same F0 | default restart still Complete accepted=8 and ArgMin_F |
| R6 | same STOPD | `D_test={cpu,gpu}`: localstop accepted=2 argmin cpu 136; no gpu |
| R7 | same STOP | no `winner=`, no `pi=` |

## Pareto-aware Next (v0.4.11)

**Executable.** `--s2c2-walk=nxt=pareto`. Design:
[`search-pareto-nxt.md`](search-pareto-nxt.md). Same `N` / `S` /
`Rst` / `Acc`; only `Nxt = first(Pareto(Frontier))`.

| ID | File | Checks |
| -- | ---- | ------ |
| P1 | `test/Analysis/s2c2-walk.mlir` PARETO | `nxt=pareto`; oracle `first(Best)!=first(Pareto)` on incomparable vectors |
| P2 | same PARETO | `@r4` trajectory equals W1 (contention-monotone Score_3) |
| P3 | same PARETO | after Complete, `pareto count=4` matches `--s2c2-argmin` |
| P4 | same PARETO | no `winner=`, no `pi=` |
| P5 | same IR | `sched.concurrent` unchanged |
| P6 | same PSTOP | `restart=false` still LocalStop argmin 129 ≠ ArgMin_F 128 |

## Search Verification (v0.4.12)

**Executable.** `--s2c2-walk=verify`. Design:
[`search-verification.md`](search-verification.md). S1–S8 of that
document; IDs here are SV1–SV8 (not v0.4.1 S1–S6).

| ID | File | Checks |
| -- | ---- | ------ |
| SV1 | `test/Analysis/s2c2-search-verify.mlir` S1 | `verify nxt-total=1`; decisions are step or localstop |
| SV2 | same | two `--s2c2-walk=verify` traces `diff` equal |
| SV3 | same S3 / AMIN | `complete accepted=8 \|X\|=8`; argmin count=4 |
| SV4 | same S4 | LocalStop accepted=4 argmin 129; no complete / 128 |
| SV5 | same S5 | accepted grows 4 → 6 → 8; restart between |
| SV6 | same S6 | `verify ok=1` State invariants; no `ok=0` |
| SV7 | same S7 | `nxt=pareto` oracle + complete + pareto count=4 |
| SV8 | same S8 | `sched.concurrent`; no `memref.copy` / `winner=` / `pi=` |

## Realization Transformation (v0.5.0)

**Frozen.** `--s2c2-xform=kind=id`. Design:
[`realization-transform.md`](realization-transform.md). Identity
only; rebuilds `X'`. Not Search.

| ID | File | Checks |
| -- | ---- | ------ |
| X1 | `test/Analysis/s2c2-xform.mlir` ID | `kind=id`; `hb-eq=1` |
| X2 | same ID / ENUM | `x-rebuilt count=8` matches `--s2c2-enumerate` |
| X3 | same IR | `sched.concurrent`; no `sched.pipeline` / `memref.copy` |
| X4 | same ID | no `winner=`, `pi=`, `s2c2-walk`, `s2c2-search` |

## Concurrent sibling reorder (v0.5.1)

**Frozen.** `--s2c2-xform=kind=concurrent-reorder`. Design:
[`realization-transform-reorder.md`](realization-transform-reorder.md).
First `P' ≠ P` inhabitant. Accept iff `HB(P') = HB(P)`. Rebuild
`X'`. Not Search.

| ID | File | Checks |
| -- | ---- | ------ |
| XR1 | `test/Analysis/s2c2-xform-reorder.mlir` OUT | r4 `accepted=1`; `hb-eq=1` |
| XR2 | same OUT | `wait_sibling` `accepted=0`; wait still after producer |
| XR3 | same OUT | r4 `hb-eq=1` after actual graph compare |
| XR4 | same ENUM | `x-rebuilt count=8` matches `--s2c2-enumerate` on `P` and `P'` |

## Transformation Composition / Legality (v0.5.2)

**Frozen.** Docs-only. No compose pass, no new `kind`. Design:
[`realization-transform-compose.md`](realization-transform-compose.md).
`(T_b ∘ T_a)` is one `T`. Each successful step re-proves
`HB(P_i) = HB(P_0)` and rebuilds `X_i`. Failure restores `P_0`.

| ID | File | Checks |
| -- | ---- | ------ |
| XC1 | paper | `T_id ∘ T_id = T_id`; origin HB holds |
| XC2 | paper | `T_id ∘ T_reorder = T_reorder` when reorder accepts |
| XC3 | paper | `T_b = ⊥` after `T_a` succeeds ⇒ composite `⊥`, `P_0` unchanged |
| XC4 | paper | origin gate is a rebuilt edge-set compare, not transitivity |
| XC5 | paper | `X_i = Enum_F(P_i)`; not `X_{i-1}` |
| XC6 | paper | no `--s2c2-xform=compose`, no `s2c2-search`, no third kind |

## Pilot / Research Validation

**Frozen V1–V2.** Not v0.5.x. Design:
[`pilot-benchmark.md`](pilot-benchmark.md). Three stand-in
workloads. V3/V4 (real latency) need a backend.

| ID | File | Checks |
| -- | ---- | ------ |
| PA1 | `test/Pilot/s2c2-pilot-workloads.mlir` | `--check-s2c2-execution` |
| PA2 | same ENUM | each func `count=8` |
| PA3 | same ARG / GPU | A argmin 130; B 128; C 163 (gpu-async) |
| PA4 | same XF / IR | reorder accepts only B; C keeps pipeline |

## CUDA Measurement Adapter (v0.1)

**Frozen protocol in CI.** Measurement stand-in, not a
backend. Not v0.5.x. Design:
[`backend-adapter-cuda.md`](backend-adapter-cuda.md). Timed
CUDA lives in `runtime/cuda/` and is not part of `check-s2c2`.
V3 is not claimed.

| ID | File | Checks |
| -- | ---- | ------ |
| CA1 | `test/Pilot/s2c2-cuda-adapter-protocol.mlir` | `--dry-run` binds `gpu-async`/`gpu` |
| CA2 | same | Score_3 A=130 B=128 C=163 |
| CA3 | same | construct map; `v3=not-claimed` |

## V3 Measurement Campaign (v0.1)

**Not Cost v0.4.** Design:
[`v3-measurement-campaign.md`](v3-measurement-campaign.md).
Timed sweep is optional `runtime/cuda/sweep.sh`. No FileCheck
of microseconds.

| ID | File | Checks |
| -- | ---- | ------ |
| VC1 | paper | `provisioned=1` on B times SiLU ∥ HtoD, not two HtoD |
| VC2 | paper | Score_3 stays 130 / 128 / 163 |
| VC3 | paper | `v3=not-claimed`; no Cost rewrite |

## V3 Measurement Metadata (v0.1)

**Not Cost v0.4.** Design:
[`v3-measurement-metadata.md`](v3-measurement-metadata.md).
Schema only in CI. JSONL/CSV live in `runtime/cuda/record_v3.py`.
No FileCheck of microseconds.

| ID | File | Checks |
| -- | ---- | ------ |
| VM1 | `test/Pilot/s2c2-v3-metadata-protocol.mlir` | required fields present; runtime source is `cudaRuntimeGetVersion` |
| VM2 | same CSV | header matches the frozen column list |
| VM3 | paper | 36 GPU points; no credentials in records |

## V3 Capability Matrix (v0.1)

**Not Cost v0.4.** Design:
[`v3-capability-matrix.md`](v3-capability-matrix.md). Schema
and host protocol only in CI. No FileCheck of microseconds.

| ID | File | Checks |
| -- | ---- | ------ |
| VX1 | `test/Pilot/s2c2-v3-capability-matrix.mlir` | `--dry-run --cap` lists arms; `score3=not-applicable` |
| VX2 | same ABC | `--dry-run` without `--cap` stays A/B/C |
| VX3 | same fixture | `--analyze-cap` prints verdicts; `v3=not-claimed` |

## V3 Overlap Phase Diagram (v0.1)

**Not Cost v0.4.** Design:
[`v3-overlap-phase.md`](v3-overlap-phase.md). Reuses matched
C∥HtoD bodies. No FileCheck of microseconds.

| ID | File | Checks |
| -- | ---- | ------ |
| VP1 | `test/Pilot/s2c2-v3-overlap-phase.mlir` | `--dry-run --phase` lists arms and axes |
| VP2 | same ABC | `--dry-run` without `--phase` stays A/B/C |
| VP3 | same fixture | `--analyze-phase` prints dominance; `v3=not-claimed` |

## V3 Pipeline Depth (v0.1)

**Not Cost v0.4.** Design:
[`v3-pipe-depth.md`](v3-pipe-depth.md). 2-stage C∥HtoD,
`depth ∈ {1,2,3,4}`. No FileCheck of microseconds.

| ID | File | Checks |
| -- | ---- | ------ |
| PP1 | `test/Pilot/s2c2-v3-pipe-depth.mlir` | `--dry-run --pipe` lists depths; `tiles=8` |
| PP2 | same ABC | `--dry-run` without `--pipe` stays A/B/C |
| PP3 | same fixture | `--analyze-pipe` prints speedup; `v3=not-claimed` |

## V3 Pipeline Tiles Sanity (v0.1)

**Not Cost v0.4.** Design:
[`v3-pipe-tiles.md`](v3-pipe-tiles.md). Same C∥HtoD pair
and depths; `tiles ∈ {4, 8, 16, 32}`. Does not change
`--pipe` default `tiles=8`. No FileCheck of microseconds.

| ID | File | Checks |
| -- | ---- | ------ |
| PT1 | `test/Pilot/s2c2-v3-pipe-tiles.mlir` | `--dry-run --pipe-tiles` lists 4/8/16/32 |
| PT2 | same ABC | `--dry-run` without `--pipe-tiles` stays A/B/C |
| PT3 | same | `--dry-run --pipe` still `tiles=8` |
| PT4 | same fixture | `--analyze-pipe-tiles` prints sat; `v3=not-claimed` |

## CUDA Validation V1 (P0)

**Not Cost v0.4.** Design:
[`v3-cuda-validation.md`](v3-cuda-validation.md). Semantic
map + default vs named-nonblocking C∥HtoD. No FileCheck of
microseconds. Semantics unchanged.

| ID | File | Checks |
| -- | ---- | ------ |
| CV1 | `test/Pilot/s2c2-v3-cuda-validation.mlir` | `--dry-run --cuda-val` lists V1 map |
| CV2 | same ABC | `--dry-run` without `--cuda-val` stays A/B/C |
| CV3 | same | `--dry-run --pipe` still `tiles=8` |
| CV4 | same fixture | `--analyze-cuda-val` prints extra-hb; `v3=not-claimed` |

## CUDA Validation V2 (pinned vs pageable)

**Not Cost v0.4.** Design:
[`v3-cuda-mem.md`](v3-cuda-mem.md). Same named-nonblocking
streams; host residency pinned vs pageable. Does not change
V1 `--cuda-val=p0` timed bodies. No FileCheck of
microseconds. Semantics unchanged.

| ID | File | Checks |
| -- | ---- | ------ |
| CM1 | `test/Pilot/s2c2-v3-cuda-mem.mlir` | `--dry-run --cuda-val-mem` lists V2 map |
| CM2 | same V1 | `--dry-run --cuda-val` stays V1 |
| CM3 | same ABC | `--dry-run` without flags stays A/B/C |
| CM4 | same fixture | `--analyze-cuda-val-mem` prints extra-hb; `v3=not-claimed` |

## V3 Capability Schema v1

**Not Cost v0.4.** Design:
[`v3-capability-schema.md`](v3-capability-schema.md).
Hardware-agnostic record. 4090 is one projection, not a new
sweep. No FileCheck of microseconds. Semantics unchanged.

| ID | File | Checks |
| -- | ---- | ------ |
| CS1 | `test/Pilot/s2c2-v3-capability-schema.mlir` | `--dry-run --cap-schema` lists v1 fields |
| CS2 | same ABC | `--dry-run` without `--cap-schema` stays A/B/C |
| CS3 | same | `--dry-run --cap` still lists `#55` arms |
| CS4 | same fixture / 4090 catalog | `--analyze-cap-schema`; `depth-star=not-a-law` |
