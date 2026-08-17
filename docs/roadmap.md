# S²C² IR Roadmap

## Phase 1 — Core dialects (this tree)

GitHub project: `s2c2ir`, based on MLIR `examples/standalone`.

Implement first-class IR for:

- `stor` — storage spaces and buffers
- `comp` — high-level compute (including `gated_mlp`)
- `comm` — copy / stream / barrier
- `sched` — async tokens, wait, compute/comm overlap, pipeline stages

Goals:

- Round-trip parse/print
- Verifiers for shape/space mismatches
- One lowering: `stor` → `memref`
- Integration IR for SSD-streaming Gated MLP with overlap

Non-goals:

- Forking IREE / XLA / TVM
- Full codegen
- Python bindings

## Phase 2 — Reuse MLIR native dialects

Lower S²C² into existing dialects instead of reimplementing them:

```text
stor  → memref (+ async)
comp  → linalg → vector / scf
comm  → mpi / memref.copy / async
sched → transform / async
```

Optional frontend:

```text
PyTorch / JAX → StableHLO → S²C²
```

## Phase 3 — Runtime / multi-backend

After the IR semantics are independently validated:

```text
S²C² → Linalg / Async / Stream-like IR → IREE HAL
                                      → LLVM CPU
                                      → GPU / NPU / CIM (later, CIRCT-like HW model)
```

IREE is a **runtime and deployment backend**, not the IR definition base.
