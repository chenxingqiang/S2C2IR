# S²C² IR Roadmap

## Phase 1 — Core dialects

GitHub project: `s2c2ir`, based on MLIR `examples/standalone`.

Four dialects: `stor`, `comp`, `comm`, `sched`. Round-trip, verifiers, and
`stor` → `memref`. Integration: SSD-streaming Gated MLP.

## Phase 1.5 — Semantic normalization (this tree)

Design: [`docs/design/phase1.5-semantic-normalization.md`](design/phase1.5-semantic-normalization.md)

| Contract | Mechanism |
| -------- | --------- |
| Logical object vs residency | `!stor.object` + `stor.materialize` / `stor.transfer` |
| Unified events | `!sched.token` from task / stream / optional copy |
| N-way concurrency | `sched.concurrent` + `sched.task` (`overlap` is 2-way sugar) |
| Target space mapping | `--convert-stor-to-memref=space-map=...` |
| Composite compute | `gated_mlp` stays fused; `--expand-comp-composites` is opt-in |

Do **not** start StableHLO or IREE until this layer is stable.

## Phase 2A — Sequential / blocking baseline

Design: [`docs/design/phase2a-sequential-lowering.md`](design/phase2a-sequential-lowering.md)

```text
comp  → linalg / tensor / math     (--convert-comp-to-linalg)
sched → sequential IR              (--sequentialize-s2c2-schedule)
stor/comm → memref + bufferization (--convert-stor-to-memref / --convert-comm-to-memref)
```

Pipeline: `--s2c2-lower`. This is a **legal total-order + blocking
approximation**, not the S²C² semantic definition and not async
lowering. Tokens are dropped because copies are synchronous.

```text
Sequential lowering  ≠  S²C² semantic definition  ≠  async lowering
```

## Execution semantics

Design: [`docs/design/execution-semantics.md`](design/execution-semantics.md)

```text
S²C²  =  Storage + Compute + Communication + Execution Semantics
```

Schedule is the HB / event constraint layer, not a fourth data dialect.
Phase 2B realizes this spec; the contracts are frozen (next section).

## Phase 2B — Execution semantics (frozen)

Design: [`execution-semantics.md`](design/execution-semantics.md),
[`pipeline-semantics.md`](design/pipeline-semantics.md),
[`phase2b-composition.md`](design/phase2b-composition.md).

```text
Token        = Event / SW                         ✅
Concurrent   = NoOrderingRequirement              ✅
Pipeline     = StageOrder (valueless stages)      ✅
Composition  = Token + Concurrent + Pipeline      ✅
```

```text
HB = TC(PO ∪ SW ∪ ConstructOrder)
```

Oracle: `--check-s2c2-execution` (E1–E8). Composition: X1. Conflict /
Race Analysis (unordered conflicting writes) remains future — not in
the oracle.

HB-preserving lowering (not “async works”):

```text
--convert-s2c2-token-to-async
--convert-s2c2-concurrent-to-async
--convert-s2c2-pipeline-to-async
```

Do **not** extend this layer with:

```text
StageResult / cross-stage SSA
iteration IR / InstanceOrder realization
SoftPipe
overlap optimization
race / conflict analysis
```

Those would change execution semantics. Next work is **hardware
capability / target mapping** (CPU sequential, GPU async, NPU staged
DMA, multi-device comm, SSD→DRAM→device). Mapping must preserve `→HB`;
it must not redefine Token, Concurrent, or Pipeline.

Design: [`capability-mapping.md`](design/capability-mapping.md). v0.1 is
a verification matrix over existing passes, not a new dialect.

## Cost / resource model (v0.1)

Design: [`cost-resource-model.md`](design/cost-resource-model.md).

```text
Cost = C_compute + C_storage + C_communication + C_synchronization − C_overlap
```

Scores semantic IR against a device capability table (`--s2c2-cost`).
Does not search, place, or redefine Token / Concurrent / Pipeline.
`C_overlap` requires unordered siblings **and** `canOverlap`.
v0.1 is **frozen**. HB-aware pair credit is
[`cost-resource-model-v02.md`](design/cost-resource-model-v02.md)
(`--s2c2-cost-hb`), also **frozen**. CanonicalRealizationCost is
[`cost-resource-model-v03.md`](design/cost-resource-model-v03.md)
(`--s2c2-cost-cp`), also **frozen**: still score-only, not search.

## Realization Space (v0.4.0)

**Frozen.** Design: [`realization-space.md`](design/realization-space.md).

```text
R(P, D) = { M | IsLegal(P, D, M) ∧ HB_M = HB_source }
```

Membership is HB equality, not refinement. Lowering may still use
`HB_source ⊆ HB_impl` as implementation correctness; that `⊆` is not
`R` membership.

## Search / Pareto (v0.4.1)

**Frozen.** Design: [`search-pareto.md`](design/search-pareto.md).

```text
ArgMin(P, D) = argmin_{M ∈ R(P, D)} Score_3(M).total   ⊆ R(P, D)
Pareto(R) over (T_HB, C_contention, C_capacity)
```

Selects among frozen `R`. Does not rewrite `P`, add HB, or treat `π`
as a decision variable. Does not change v0.1–v0.3 scores.

## Realization Enumerator (v0.4.2)

**Frozen.** Design: [`realization-enumerator.md`](design/realization-enumerator.md).

```text
Enum_F    = R(P, D) ∩ F
ArgMin_F  = argmin_{M ∈ Enum_F} Score_3(M).total
Pareto_F  = Pareto(Enum_F)
```

`ArgMin_F` is not, in general, `ArgMin_R ∩ F`. Lists members of frozen
`R` inside a declared finite family. `--s2c2-enumerate` (**v0.4.3 frozen**) prints that list
(`Output = R ∩ F` via `isLegalRealization`). `--s2c2-argmin`
(**v0.4.4 frozen**) prints set-valued `ArgMin_F` / `Pareto_F` over
`Enum_F`. Does not pick a unique `M*`, rewrite `P`, or generate new
space maps. Search Space / `Neighbor` / `LegalNeighbor`
(**v0.4.5**, [`search-space.md`](design/search-space.md)) are the
next design objects. The walk contract
(**v0.4.6**, [`search-algorithm-contract.md`](design/search-algorithm-contract.md))
names State, Generated/Accepted, termination, score cache, tie
preservation, and next-state policy. `Neighbor` generates in `F`
and does not imply `R`. Start / restart
(**v0.4.7**, [`search-start-policy.md`](design/search-start-policy.md))
name how a walk enters `X` and re-enters after `LocalStop`. No
`--s2c2-search` yet. `StartFirst` is a witness kind, not the
algorithm. The Algorithm object
(**v0.4.8**, [`search-algorithm.md`](design/search-algorithm.md))
is `A = (N, S, Rst, Nxt, Acc)` with
`Nxt : State → LegalNeighbor ∪ {⊥}`. `--s2c2-walk`
(**v0.4.9 frozen**, [`search-walk-n1.md`](design/search-walk-n1.md)) is the
Hamming-1 inhabitant (`StartFirst` / `StartUnused` / `first(Best)`).
Restart / Complete coverage
(**v0.4.10 frozen**, [`search-restart-complete.md`](design/search-restart-complete.md))
witnesses `LocalStop ⇏ ArgMin_F` via `--s2c2-walk=restart=false`
without a new algorithm. Pareto-aware Next
(**v0.4.11 frozen**, [`search-pareto-nxt.md`](design/search-pareto-nxt.md))
is `Nxt = first(Pareto(Frontier))`; default `nxt=scalar` is unchanged.
Search Verification
(**v0.4.12 frozen**, [`search-verification.md`](design/search-verification.md))
asserts inhabitant invariants via `--s2c2-walk=verify` (S1–S8).
No third `Nxt`. Realization Transformation
(**v0.5.0 frozen**, [`realization-transform.md`](design/realization-transform.md))
opens `T : P → P' ∪ {⊥}` with `HB(P') = HB(P)` only when
`T(P) ≠ ⊥`, and rebuilt `X'`.
`--s2c2-xform=kind=id` is the identity witness, not a searcher.
Concurrent sibling reorder
(**v0.5.1 frozen**, [`realization-transform-reorder.md`](design/realization-transform-reorder.md))
is the first `P' ≠ P` inhabitant; it accepts only when the
rebuilt HB graphs are equal. Transformation composition
(**v0.5.2 frozen**, [`realization-transform-compose.md`](design/realization-transform-compose.md))
is docs-only: `(T_b ∘ T_a)` is one `T`; each step re-proves
`HB(P_i) = HB(P_0)` and rebuilds `X_i`. Not a second kind.

## Pilot / Research Validation

**V1–V2 frozen.** Not v0.5.x. Design:
[`pilot-benchmark.md`](design/pilot-benchmark.md).
Three stand-in workloads (SSD→HBM→Compute, Compute∥Comm,
Pipeline) run frozen Enum / ArgMin / Cost / HB-preserving
reorder. Architecture expansion pauses here; do not open
v0.5.4. Real-latency correlation (V3) needs a backend; it
is not this section.

## CUDA measurement adapter (v0.1)

**Frozen stand-in.** Not a CUDA backend. Not v0.5.x. Design:
[`backend-adapter-cuda.md`](design/backend-adapter-cuda.md).
Binds the three Pilot shapes to one legal `M`
(`gpu-async` / `gpu`) and times a CUDA stand-in. Does not
parse IR, change Cost / HB / `R`, or claim V3. B's two HtoD
copies are adapter provisioning, not a Cost axiom.

## V3 Measurement Campaign (v0.1)

**Not Cost v0.4.** Design:
[`v3-measurement-campaign.md`](design/v3-measurement-campaign.md).
Sweeps `N`, SiLU repeats `k`, and `provisioned` (IR work vs
adapter HtoD). Still does not claim V3.

## V3 Measurement Metadata (v0.1)

**Not Cost v0.4.** Design:
[`v3-measurement-metadata.md`](design/v3-measurement-metadata.md).
Fixes the JSONL/CSV record before a 4090 rerun. Adapter
semantics unchanged.

## Phase 2C — Compute frontend (optional)

```text
PyTorch / JAX → StableHLO → S²C²
```

## Phase 3 — Runtime / multi-backend

```text
S²C² → Linalg / Async → IREE HAL
                      → LLVM CPU
                      → GPU / NPU / CIM
```

IREE is a **runtime and deployment backend**, not the IR definition base.
