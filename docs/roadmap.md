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
