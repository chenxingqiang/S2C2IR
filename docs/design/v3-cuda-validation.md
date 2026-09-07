# CUDA Target Validation Matrix v1

Status: **V1 P0 4090 evidence recorded**. Not Cost v0.4. Does
**not** change Cost, HB axioms, `R`, Search, Transformation,
Pilot IR, A/B/C bodies, `--matched` / `--phase` / `--cap` /
`--pipe` timed bodies, or S²C² Semantics. Baseline:
`751dd11` (`#58`).

```text
CUDA Validation     ≠  “4090 supports overlap”
--cuda-val          ≠  a new Pilot func
default stream      ≠  sched.concurrent
Semantic            ≠  Capability  ≠  Runtime
depth* = N_resource ≠  a law
V3                  ≠  claimed
```

---

## 1. Why this layer

`#55`–`#58` closed one 4090 evidence chain on **one** pair.
The next question is not another C∥HtoD speedup. It is
whether the S²C² abstractions still map, without extra
happens-before and without false performance conclusions,
onto CUDA’s real execution boundary:

```text
S²C² Semantic
      ↓
CUDA Realization
      ↓
Observed HB / Capability
```

CUDA streams are in-order per stream. Distinct streams
**may** overlap; they do not **guarantee** overlap.
Concurrency is `f(pair, direction, size, r, resource,
stream, sync, memory, device)`, not `f(GPU)` and not
`f(two streams)`.

This campaign looks for **counterexamples**: CUDA behavior
the current Storage / Compute / Communication / HB /
Capability / Schedule vocabulary cannot express, or
places where the mapping would invent performance.

---

## 2. Five PRs (do not ship in one)

| PR | Name | Asks |
| -- | ---- | ---- |
| V1 | Semantics / stream / HB | Does the mapping preserve HB? Where does CUDA add implicit HB? |
| V2 | Memory / Storage | pinned vs pageable vs managed vs `MallocAsync` |
| V3 | Communication | HtoD / DtoH / D2D / P2P / bidirectional |
| V4 | Compute / resource | light vs heavy `C∥C`; occupancy |
| V5 | Execution | stream count, Graph, multi-GPU |

Capability schema (`#59` / Phase 3A) is the **record
type**. These PRs fill cells. They do not rewrite Cost.
The compiler consumes the catalog via
`--s2c2-capability-query` / `--s2c2-capability-schedule`
([`capability-aware-schedule.md`](capability-aware-schedule.md)).

P0 counterexamples (this campaign’s order, not all in V1):

```text
C∥HtoD  named-nonblocking  vs  legacy default stream
pinned vs pageable HtoD
cudaMallocAsync + cross-stream wait
C_heavy∥C_heavy  vs  C_light∥C_light
HtoD∥DtoH across sizes
```

P1 later: D2D, P2P, stream-count, CUDA Graph, unified
memory.

---

## 3. V1 — Semantic mapping (this increment)

### 3.1 Required map (protocol)

| S²C² | CUDA realization | Must show |
| ---- | ---------------- | --------- |
| `stor.materialize` | `cudaMalloc` | allocation ≠ valid |
| `stor.transfer` | `cudaMemcpyAsync` | completion → dest valid |
| `comm.copy` | `cudaMemcpyAsync` | event-preserving |
| `sched.wait` | `cudaStreamWaitEvent` | SW / HB |
| `sched.concurrent` | named non-default streams | no implicit sibling HB |
| `sched.pipeline` | chained stream/event | StageOrder (listed, not retimed here) |
| task event | `cudaEventRecord` | completion witness |

Acceptance is **not** “the binary ran.” It is:

```text
HB_S²C²  ⊆  HB_CUDA realization
```

and we hunt the opposite:

```text
HB_CUDA  \  HB_S²C²     extra / implicit sync
```

### 3.2 P0 probe: default vs named-nonblocking

Same remaining work as `--matched` / `--phase`:

```text
1× HtoD(H) + k× SiLU(D)     D ≠ H
pair = C ∥ HtoD
```

Two realizations of the **same** S²C² Concurrent shape:

```text
named     cudaStreamCreateWithFlags(..., NonBlocking)
default   both sides on the legacy NULL stream
```

Correctness is gated (adapter exits if dest ≠ reference).
Timing is separate. Verdict uses the frozen `#55` policy
(`hid_short=1.15`, `near_sum=0.90`) as a **classifier**,
not a Cost axiom.

What would count as a useful counterexample:

```text
named:     T_ovl ≈ max     extra_hb = none
default:   T_ovl ≈ sum     extra_hb = legacy-default
```

That would show:

```text
sched.concurrent  =  logical no-order
                  ≠  “a CUDA stream API produces overlap”
```

`k` is chosen per N so tile `r ≈ 1` from `T_compute(k=1)`,
same policy as `#57`. N ∈ {4M,16M,64M}.

Arms: `val-{copy,compute,seq,ovl}-{named,default}`.
Eight arms × 3 N = **24** points.

Do not FileCheck microseconds.

---

## 4. Out of this increment

```text
V2 pageable / managed / MallocAsync
V3 D2D / P2P
V4 C_heavy∥C_light
V5 stream-count / Graph / multi-GPU / Nsight
rewriting C_overlap / Capability_4090 / Cost v0.4
changing S²C² Semantics
claiming V3
```

---

## 5. Files

| Path | Role |
| ---- | ---- |
| `runtime/cuda/s2c2_cuda_adapter.cu` | `--cuda-val=` P0 arms |
| `tools/s2c2-cuda-adapter/` | host `--dry-run --cuda-val` |
| `runtime/cuda/record_v3.py` | `--cuda-val-sweep` / `--analyze-cuda-val` |
| `docs/design/v3-dataset/v3-cuda-val.jsonl` | 24-point 4090 records (after sweep) |

`--matched` / `--phase` / `--cap` / `--pipe` bodies stay
untouched.

---

## 6. RTX 4090 V1 P0 (24 points → 6 slices)

Same 4090 / driver 570.124.06 / runtime 12080. All arms
printed `correct=1` (adapter exits on mismatch).
Records: [`v3-dataset/v3-cuda-val.jsonl`](v3-dataset/v3-cuda-val.jsonl).
Derived: [`v3-dataset/v3-cuda-val-slices.csv`](v3-dataset/v3-cuda-val-slices.csv).

| N | stream | r | T_copy | T_compute | T_seq | T_ovl | ovl/max | ovl/sum | verdict |
| - | ------ | - | ------ | --------- | ----- | ----- | ------- | ------- | ------- |
| 4M | named | 0.607 | 670 | 407 | 1076 | 741 | 1.105 | 0.688 | parallel |
| 4M | default | 0.610 | 670 | 409 | 1075 | 1079 | 1.610 | 1.000 | serial |
| 16M | named | 1.102 | 2660 | 2931 | 5636 | 2987 | 1.019 | 0.534 | parallel |
| 16M | default | 1.102 | 2660 | 2931 | 5630 | 5571 | 1.901 | 0.996 | serial |
| 64M | named | 1.093 | 10612 | 11594 | 22199 | 11903 | 1.027 | 0.536 | parallel |
| 64M | default | 1.093 | 10613 | 11597 | 22203 | 22208 | 1.915 | 1.000 | serial |

```text
named:    T_ovl ≈ max     extra_hb = none      parallel at all 3 N
default:  T_ovl ≈ seq ≈ sum   extra_hb = legacy-default   serial at all 3 N
counterexamples = 3 / 3
```

So the **same** S²C² Concurrent remaining work is max-like
on named nonblocking streams and sum-like on the legacy
NULL stream. That is extra HB in the CUDA realization, not
a change of S²C² semantics.

```text
sched.concurrent  =  logical no-order
                  ≠  “CUDA streams produce overlap”
HB_S²C²           ⊆  HB_named
HB_default        \  HB_S²C²   =  legacy default-stream sync
```

Do not FileCheck microseconds. Do not promote this to a
Cost axiom or a Schedule rewrite.

```text
CUDA Validation  ≠  Cost v0.4
extra HB         ≠  a Schedule rewrite
Semantics        =  unchanged
V3               ≠  claimed
```

Pinned vs pageable (V2 P0) is a separate increment:
[`v3-cuda-mem.md`](v3-cuda-mem.md). It does not change this
V1 P0 surface.
