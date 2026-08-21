# Cost / Resource Model (v0.1)

Status: **design + score-only analysis**. Does **not** change Phase 2B
execution semantics and does not pick a lowering. Prerequisite:

[`capability-mapping.md`](capability-mapping.md) (legal realizations),
[`execution-semantics.md`](execution-semantics.md) (frozen HB).

```text
Lowering_target may realize HB, but must not redefine HB
```

Capability mapping already answered *is this realization legal?*
This layer starts answering *among legal realizations, which is better?*

```text
Cost model  ≠  execution semantics
Cost        =  score of (S²C² IR, device capability)
```

v0.1 **scores**; it does not search, place, or rewrite. Auto-scheduling
and backend specialization are later.

---

## 1. What is scored

Hardware-agnostic dimensions, not CUDA L2 / NPU ISA:

```text
Cost = C_compute + C_storage + C_communication + C_synchronization
       − C_overlap
```

Units are integer **ticks**. Device profiles supply throughputs; the IR
supplies residencies, movement, compute, and schedule structure.

| Term | IR sources | Device knob |
| ---- | ---------- | ----------- |
| `C_compute` | `comp.elemwise` / `matmul` / `gated_mlp` | `computeThru` |
| `C_storage` | `stor.materialize` / `stor.alloc` bytes | (identity in v0.1) |
| `C_communication` | `pack` / `transfer` / `copy` / `stream` | `bw[space]` |
| `C_synchronization` | `sched.wait` / `comm.barrier` | `waitCost` |
| `C_overlap` | `sched.concurrent` / `sched.overlap` | `canOverlap` |

```text
C_overlap > 0  only if the IR has unordered siblings
               AND the device can overlap
```

That consumes Concurrent = `NoOrderingRequirement`. It does **not**
add sibling HB. Pipeline `StageOrder` is sequential in the score
(no overlap *between* stages), matching frozen v0.1.

A sequential legal realization (`canOverlap=false`, e.g. CPU-like)
has `C_overlap = 0` even when the source contains `sched.concurrent`.

---

## 2. Device profiles (v0.1)

Built-in names: `cpu`, `gpu`, `npu`, `cim`. These are capability
tables, not backends.

| | computeThru | waitCost | canOverlap | bw ssd / dram / hbm / sram |
| --- | ---: | ---: | --- | --- |
| cpu | 1 | 1 | no | 1 / 4 / 8 / 16 |
| gpu | 8 | 1 | yes | 1 / 8 / 32 / 32 |
| npu | 16 | 1 | yes | 1 / 8 / 16 / 64 |
| cim | 32 | 8 | no | 1 / 4 / 4 / 8 |

`computeThru` is ticks-per-flop inverted (flops / thru). Link bandwidth
of a transfer is `min(bw[src], bw[dst])`. Pack uses destination space
only.

v0.1 does not model queue depth, programming-vs-MVM split beyond CIM
`waitCost`, or DRAM/HBM capacity limits as a hard constraint.

---

## 3. Work estimates

Static shapes only; dynamic → 0 (not guessed).

| Op | Work |
| -- | ---- |
| elemwise | `numel` |
| matmul `A[M,K] B[K,N]` | `2·M·N·K` |
| gated_mlp `x[B,K], Wg/Wu[K,H], Wd[H,N]` | `4·B·K·H + 2·B·H·N + B·H` |
| buffer payload | `numel · (bitwidth/8)` |

Integer division rounds up: `(n + d − 1) / d`.

---

## 4. Pass

```text
--s2c2-cost=device=cpu|gpu|npu|cim
```

Score-only on **semantic S²C² IR**. It does not rewrite the module and
does not run after `--s2c2-lower` as a memref cost model.

Prints one line per function on stderr:

```text
s2c2-cost device=cpu func=k1 compute=… storage=… communication=… synchronization=… overlap=… total=…
```

`total = max(0, sum of first four − overlap)`.

---

## 5. Out of scope

```text
StageResult / iteration IR / SoftPipe / race analysis
search / auto-scheduling / placement
IREE, StableHLO, MPI, CUDA, NPU ISA
redefining Token / Concurrent / Pipeline
```

---

## 6. Tests

| ID | File | Claim |
| -- | ---- | ----- |
| K1 | `test/Analysis/s2c2-cost.mlir` | same concurrent IR: CPU `overlap=0`, GPU `overlap>0` |
| K2 | same | no concurrent: `overlap=0` on CPU and GPU |
| K3 | same | pipeline stages: GPU still `overlap=0` (StageOrder ≠ overlap) |
| K4 | same | `sched.wait` counts in `synchronization` |
