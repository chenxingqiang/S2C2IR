# S²C² CUDA Backend Adapter (v0.1)

Status: **measurement adapter frozen**. Not an S²C² CUDA
backend. Not v0.5.x. Does **not** add a `T` kind, Search,
Cost axiom, or HB/`R` change. Architecture v0.5.0–v0.5.2 and
Pilot V1–V2 stay frozen at `e69bf69` (`#45`). Adapter merged
as `090b247` (`#46`). This layer is the fixed CUDA
measurement entry:

```text
S²C² Pilot  →  one legal M  →  CUDA stand-in  →  latency
```

```text
Adapter          ≠  compiler backend
Adapter          ≠  Search / Transform
Score_3          ≠  physical predictor
tensor<8xf32>    ≠  measurement payload
logical SSD      ≠  a real disk
V3               ≠  claimed in this document
```

---

## 1. Why an adapter, not a backend

The frozen stack already ranks realizations. V3 asks whether
that rank matches hardware:

```text
Rank(Cost)  ≈  Rank(Latency)
```

A production S²C² → CUDA compiler is out of scope. v0.1 binds
the three frozen Pilot *shapes* to CUDA primitives and times
them. It does not parse IR, emit kernels from MLIR, or change
`IsLegal` / `Score_3`.

One legal `M` only:

```text
M = (sched=gpu-async, map=default, device=gpu)
```

That `M` is already in `R ∩ F_0` for each Pilot func.

---

## 2. Contract

```text
Adapter(P_id, M, N) → {score3_total, latency_us} ∪ {⊥}
```

| Input | Meaning |
| ----- | ------- |
| `P_id` | `pilot_a_ssd_hbm_compute` / `pilot_b_compute_par_comm` / `pilot_c_pipeline_three_stage` |
| `M` | frozen `gpu-async` + `default` + `gpu` |
| `N` | measurement length (floats). **Not** the IR shape |

`⊥` if `M` is not the bound GPU realization, or CUDA is absent
when a timed run is requested.

`--dry-run` prints the binding and frozen `Score_3` without a
device. That is the CI witness.

---

## 3. Residency stand-in

| Logical space | CUDA stand-in |
| ------------- | ------------- |
| SSD | page-locked host (`cudaHostAlloc`) |
| HBM | device (`cudaMalloc`) |

This is the same class of stand-in as Pilot `tensor<8xf32>`:
structural, not a storage benchmark. A later SSD adapter may
replace the host buffer with a real disk path. v0.1 must not
claim disk bandwidth.

---

## 4. Construct map (HB-preserving realization)

| S²C² | CUDA |
| ---- | ---- |
| `stor.pack` into SSD | fill pinned host |
| `comm.stream` SSD→HBM | `cudaMemcpyAsync` HostToDevice |
| `comm.stream` HBM→SSD | `cudaMemcpyAsync` DeviceToHost |
| `sched.wait` | `cudaEventSynchronize` on that copy |
| `stor.unpack` + `comp.elemwise` silu | `silu` kernel on a stream |
| Concurrent siblings | two streams; no event between them |
| Pipeline StageOrder | event after prefetch before compute; event after compute before writeback |

```text
HB_source ⊆ HB_impl
```

The adapter may be more conservative (extra device
synchronization at timing boundaries). It must not invent a
sibling wait on B, or drop StageOrder on C.

A / B / C stay distinct programs. `T_reorder` is not applied.

B's timed body issues **two HostToDevice copies** (compute
path: HtoD→scratch + SiLU; comm path: HtoD→hbm). That is
adapter-specific **data provisioning**, not a second IR
`comm.stream`. Later V3 must time IR semantic work separately
from this provisioning. Do not treat the current B/A latency
ratio as a Cost axiom.

---

## 5. Frozen Score_3 (compiler side)

Copied from Pilot FileCheck. The adapter does **not**
recompute Cost.

```text
A  GPU  130
B  GPU  128
C  GPU  163
```

Cost rank on this `M`:

```text
B  <  A  <  C
```

V3 on this slice is rank agreement of `{A,B,C}` on one GPU,
plus optional CPU stand-in of the same shapes. `n=3` is not
Spearman validation. Do not claim the model is calibrated.

---

## 6. Measurement

Default `N = 1<<24` (16M floats, 64 MiB). Warmup, then median
of several `cudaEvent` intervals.

`--device=cpu` is a host memcpy + silu path of the same
shapes, for a later CPU-vs-GPU rank check. Concurrent B on
CPU uses two threads. It is not `cpu-seq` lowering.

---

## 7. Out of scope

```text
v0.5.4 / new T kind
--s2c2-search
IR → NVVM / IREE HAL codegen
changing Cost / HB / R
real SSD / NPU
claiming hardware speedup
claiming V3 pass
```

---

## 8. One RTX 4090 observation (not V3)

Median `cudaEvent` / host chrono, same binary, one machine
(CUDA 12.8, driver 570). Payload is the measurement `N`, not
IR `tensor<8xf32>`. Do not FileCheck these numbers.

| N | A GPU μs | B GPU μs | C GPU μs | GPU latency rank | Cost rank |
| - | -------- | -------- | -------- | ---------------- | --------- |
| 4M | 696 | 1341 | 1342 | A < B ≈ C | B < A < C |
| 16M | 2741 | 5487 | 5445 | A < C < B | B < A < C |
| 64M | 11484 | 21734 | 22319 | A < B < C | B < A < C |

CPU stand-in at N=16M: A 61936, B 71090, C 73300 μs.
GPU < CPU on all three (device rank agrees with Cost).
Workload rank does **not**: Cost picks B; measured A is
~2× faster than B/C because this stand-in does two HostToDevice
copies on B and they contend.

```text
V3  observation / calibration probe
    not validated, not a Cost revision
```

`C_overlap` looks optimistic on this stand-in (copy-engine
contention). Do **not** change Cost v0.1–v0.3 from `n=3`.
Next layer is a measurement campaign, not Cost v0.4.

---

## 9. Files

| Path | Role |
| ---- | ---- |
| `tools/s2c2-cuda-adapter/` | host `--dry-run` protocol (no CUDA, no LLVM) |
| `runtime/cuda/s2c2_cuda_adapter.cu` | timed CUDA / CPU stand-in |
| `test/Pilot/s2c2-cuda-adapter-protocol.mlir` | CA1–CA3 FileCheck |
