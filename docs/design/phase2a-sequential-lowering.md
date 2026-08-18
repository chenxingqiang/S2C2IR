# Phase 2A Design: Sequential / Blocking Baseline

Status: **correctness baseline**. Does not define S²C² execution semantics.

```text
Sequential lowering  ≠  S²C² semantic definition  ≠  async lowering
```

Phase 2A proves the four S²C² dimensions can converge onto existing MLIR
dialects. It is **not** production lowering and **not** the schedule model.

```text
S²C² Semantic IR
       │
       ├── Phase 2A sequential / blocking baseline
       │      A → B → C, comm.stream → memref.copy
       │
       └── Phase 2B event-preserving lowering (later)
              A || B || C, !sched.token → !async.token
```

Non-goals: `async`, MPI, StableHLO, IREE, real overlap.

## 1. Pipeline

`--s2c2-lower`:

1. `--convert-comp-to-linalg`
2. `--sequentialize-s2c2-schedule`
3. `--convert-stor-to-memref` (also `--convert-comm-to-memref`)

`--convert-comm-to-memref` is the same **blocking memory lowering**, not
an async communication backend.

## 2. Data validity (storage / comm)

Object identity is already strict (`getLogicalObject`). Validity is a
separate, lightweight contract — **not** a `valid/stale/dirty/inflight`
state machine.

| Op | After the op (or its completion token) |
| -- | -------------------------------------- |
| `stor.materialize` | Residency **exists**; contents **unspecified** |
| `stor.alloc` | Anonymous residency exists; contents unspecified |
| `stor.transfer` | New residency exists; destination **valid** |
| `stor.pack` | Destination **valid** |
| `comm.copy` / `comm.stream` | Destination **valid** |
| `stor.unpack` | Reads; defined only if the source is valid |

```text
%w = stor.object ...
%w_ssd = stor.materialize %w    // allocated, uninitialized
%w_hbm = stor.materialize %w    // allocated, uninitialized
%t = comm.stream %w_ssd, %w_hbm // token = dest becomes valid
sched.wait %t
%y = comp.gated_mlp ... %w_hbm  // legal only after validity
```

`!sched.token` from a transfer/copy/stream means **destination is valid**.
A token from `sched.task` means **the region completed**.

Reading a materialized-but-never-filled buffer is undefined. Phase 2A
does not diagnose that; later analyses may.

## 3. `--sequentialize-s2c2-schedule` is a baseline

This pass **makes async operations synchronous** and then drops events.

1. Erase completion consumers: `sched.wait`, `comm.barrier`
2. Inline regions in one **legal total order**
3. Drop unused completion tokens

It is **not** a general schedule lowering. Future passes must not assume
`sched.wait` can be unconditionally erased.

### 3.1 `sched.concurrent`

Semantic definition (Phase 1.5):

```text
NoOrderingRequirement(A, B, C)
```

not `MustExecuteConcurrently`. Therefore

```text
SequentialSchedule ∈ ValidSchedules
```

Sequentialize inlines direct `sched.task` children in **IR order**. That
is one legal total order consistent with explicit token dependencies
(after waits are erased, the programmer is responsible for listing
producer tasks before consumer tasks when they share data).

Phase 2A / v0.1 verifier: concurrent body children **must** be
`sched.task`. Nested `pipeline` / `overlap` / `concurrent` is rejected
so the dialect contract matches lowering capability.

### 3.2 Tokens

Sequentialization **erases completion semantics**. After wait/barrier
removal, a task token with remaining uses has **escaped** the baseline
and the pass fails. Tokens are not rewritten to a dummy “already
complete” value.

### 3.3 `sched.overlap`

Communicate region first, then compute. That is a legal order that makes
side-effecting transfers complete before compute reads the destination
under the blocking approximation.

## 4. Blocking communication lowering

```text
comm.copy / comm.stream  →  memref.copy   (Phase 2A blocking approximation)
```

`memref.copy` is synchronous, so “erase wait then copy” happens to be
correct for this baseline. It does **not** lower stream’s async event
into memref. Phase 2B is event-preserving.

`stor.materialize` → `memref.alloc` (no copy).  
`stor.transfer` → `memref.alloc` + `memref.copy` (establishes validity).

## 5. Compute → linalg is a realization

| S²C² semantics | Phase 2A realization |
| -------------- | -------------------- |
| `comp.matmul`: `C = A @ B` | `linalg.fill(0)` + `linalg.matmul` (tensor dest) |
| `comp.elemwise`: canonical math | `linalg.map` + `math` / `arith` |
| `comp.gated_mlp`: fused candidate | same contract, then the above |

Zero-fill and `exp`/`erf` expansions are **not** the compute model.
Targets (CUDA, NPU, CIM) may use different instruction sequences.

## 6. Next document (not this PR)

[S²C² Execution Semantics](execution-semantics.md) is the definition.
Phase 2A remains a realization. Do not implement event-preserving
lowering until that spec is approved.
