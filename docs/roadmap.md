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

## Execution semantics (before Phase 2B)

Design: [`docs/design/execution-semantics.md`](design/execution-semantics.md)

```text
S²C²  =  Storage + Compute + Communication + Execution Semantics
```

Schedule is the HB / event constraint layer, not a fourth data dialect.
Approve this spec before any event-preserving lowering.

## Phase 2B — Implement the approved execution semantics

Do not start until `execution-semantics.md` is approved. Then realize
`→HB` (do not redefine it):

```text
event  →  runtime completion object
wait   →  await
task   →  schedulable region
concurrent → unordered launch (SW only where the spec puts it)
```

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
