# CUDA Target Validation Matrix v1

Status: **V1 protocol + P0 probe**. Not Cost v0.4. Does
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

Capability schema (`#59`, if landed) is the **record
type**. These PRs fill cells. They do not rewrite Cost.

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

```text
CUDA Validation  ≠  Cost v0.4
extra HB         ≠  a Schedule rewrite
Semantics        =  unchanged
V3               ≠  claimed
```
