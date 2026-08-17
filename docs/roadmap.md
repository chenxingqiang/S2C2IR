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

## Phase 2A — Lower S²C² to MLIR native dialects

```text
comp  → linalg / tensor / math     (--convert-comp-to-linalg)
sched → sequential IR              (--sequentialize-s2c2-schedule)
stor/comm → memref + bufferization (--convert-stor-to-memref / --convert-comm-to-memref)
```

Pipeline: `--s2c2-lower`. Tokens are dropped (blocking copies). True
`!async.token` overlap is Phase 2B.

## Phase 2B — Communication backends

```text
comm  → memref.copy / async
comm  → MPI (collectives)
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
