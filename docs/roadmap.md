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

Design: [`realization-enumerator.md`](design/realization-enumerator.md).

```text
Enum(P, D; F) = R(P, D) ∩ F
F = Sched_F × Maps_F × Dev_F     finite, declared
```

Lists members of frozen `R` inside a declared finite family. Does not
pick `M*`, rewrite `P`, or generate new space maps. Heuristic searcher
and placement remain later.

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
