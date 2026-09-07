# V3 4090 Resource / Capability Matrix (v0.1)

Status: **4090 evidence recorded**. Not Cost v0.4. Does **not**
change Cost, HB, `R`, Search, Transformation, Pilot IR, A/B/C
bodies, or the frozen matched calibration table. Baseline:
`4baecc8` (`#54`). Dataset: `f363684` (`#55`).

```text
Capability matrix  ≠  a Cost axiom
--cap              ≠  a new Pilot func
score3             ≠  applicable
V3                 ≠  claimed
```

---

## 1. Why this layer

`#51` showed Compute ∥ one HtoD hides the shorter side.
`#52` (draft) showed HtoD ∥ HtoD serializes. `#54` showed
`hidden_frac = f(r)` is not N-independent.

The next input to a later Cost is a **hardware capability
matrix**, not a formula patch:

```text
Capability_4090(pair) ∈ {parallel, serial, mixed}
T_copy(bytes)         ≈  T_launch + bytes / BW
T_sync                =  event / stream / device
T_compute(kind)       =  elementwise | reduction | matmul
```

Do not rewrite `C_overlap` from this table.

---

## 2. P0 cells (this increment)

### 2.1 Pair matrix

`N ∈ {4M,16M,64M}` floats. Compute arms use `k=32`.

| Pair | Arm | Role |
| ---- | --- | ---- |
| HtoD | `cap-htod` | single |
| DtoH | `cap-dtoh` | single |
| HtoD → DtoH | `cap-htod-dtoh-seq` | same-stream sequence |
| HtoD → event → DtoH | `cap-htod-dtoh-event` | explicit wait |
| HtoD ∥ DtoH | `cap-htod-dtoh-par` | two streams, two engines |
| HtoD ∥ HtoD | `cap-htod-htod-par` | two streams, one direction |
| DtoH ∥ DtoH | `cap-dtoh-dtoh-par` | two streams, one direction |
| Compute | `cap-compute` | k×SiLU single |
| Compute ∥ HtoD | `cap-compute-htod` | matched-style overlap |
| Compute ∥ DtoH | `cap-compute-dtoh` | missing cell from `#51` |
| Compute ∥ Compute | `cap-compute-compute` | two streams, two dests |

Verdict for a concurrent pair with singles `A`, `B`:

```text
T_par / max(A,B)   ≈ 1  and  T_par / (A+B)  ≪ 1   →  parallel
T_par / (A+B)      ≈ 1                            →  serial
otherwise                                         →  mixed
```

Slack used by the recorder (measurement, not a Cost axiom):

```text
par/sum ≥ 0.90                         →  serial
par/max ≤ 1.15  and  par/sum ≤ 0.75    →  parallel
else                                   →  mixed
```

Especially compare:

```text
T(HtoD ∥ DtoH)   vs   max(T_HtoD, T_DtoH)
T(HtoD ∥ DtoH)   vs   T_HtoD + T_DtoH
T(HtoD → event → DtoH) − T(HtoD → DtoH)
```

### 2.2 Size curve

`htod` / `dtoh` only:

```text
bytes ∈ {1KB,4KB,16KB,64KB,1MB,4MB,16MB,64MB,256MB}
n     = bytes / 4
```

Small payloads repeat inside the timer and divide.
Fit later: `T = T_launch + bytes/BW`. Not a Cost write-back.

### 2.3 Synchronization

Idle stream, inner loop, divide:

```text
cap-event-sync    record + EventSynchronize
cap-stream-sync   StreamSynchronize
cap-device-sync   DeviceSynchronize
```

The copy-path event cell in §2.1 is the non-idle counterpart.

### 2.4 Compute intensity (stand-in, not new IR)

SiLU stays the pair-matrix compute. This increment also times
two extra kernels so `comp` is not only elementwise:

| Arm | Kind | Arithmetic intensity |
| --- | ---- | -------------------- |
| `cap-compute` | elementwise SiLU | FLOPs/Bytes ≪ 1 |
| `cap-reduction` | grid reduction | FLOPs/Bytes ≪ 1 |
| `cap-matmul` | tiled GEMM, `N` = dim | FLOPs/Bytes ≫ 1 at dim ≥ 256 |

```text
AI_silu      ≈  5N / 8N     ≈  0.6
AI_reduce    ≈  N / 4N      ≈  0.25
AI_matmul(n) ≈  2n³ / 12n²  =  n/6
```

`N` on a `cap-matmul` record is the **matrix dimension**, not
a copy length. MLP / gated_mlp stay later (P2).

---

## 3. Out of this increment

```text
Pipeline depth / double buffering / stream-count
pageable vs pinned vs mapped
gated_mlp / Prefetch→Compute→Writeback
rewriting C_overlap / Score_3
claiming V3
Cost v0.4
```

Those stay later P1/P2.

---

## 4. Adapter / recorder

```text
s2c2-cuda-run --cap=htod|dtoh|htod-dtoh-seq|htod-dtoh-event|
               htod-dtoh-par|htod-htod-par|dtoh-dtoh-par|
               compute|compute-htod|compute-dtoh|compute-compute|
               event-sync|stream-sync|device-sync|
               reduction|matmul|
               pairs|sync|intensity|all
```

`--cap` default is off. A/B/C and `--matched` bodies are
unchanged. `--cap` and `--matched` must not be combined.
`score3_total=0` is a wire placeholder; records store empty
`score3`. Host `--dry-run --cap` prints the arm list.

Recorder: `record_v3.py --cap-sweep` / `--analyze-cap` /
`--print-cap-schema`. Metadata FIELDS stay frozen.

Expected 4090 count:

```text
pairs (+ event path)   11 × 3 N                 = 33
size curve             2 × 9 sizes              = 18
sync                   3
intensity              3 N reduce + 3 dim GEMM  =  6
                                              ----
                                               60
```

---

## 5. Files

| Path | Role |
| ---- | ---- |
| `runtime/cuda/s2c2_cuda_adapter.cu` | `--cap=` |
| `tools/s2c2-cuda-adapter/` | host `--dry-run --cap` |
| `runtime/cuda/record_v3.py` | `--cap-sweep` / `--analyze-cap` |
| `docs/design/v3-dataset/v3-cap.jsonl` | 60-point 4090 records |

Do not FileCheck microseconds. Do not FileCheck a Cost v0.4
rewrite.

---

## 6. RTX 4090 results (60 points)

Hardware snapshot (not a lock):

```text
gpu_model        NVIDIA GeForce RTX 4090
gpu_memory       24564
driver_version   570.124.06
cuda_runtime     12080
nvcc_version     release 12.8, V12.8.61
power_mode       limit_w=450.00
clock_state      pre-sweep snapshot (idle P8 on this run)
```

Records: [`v3-dataset/v3-cap.jsonl`](v3-dataset/v3-cap.jsonl)
(60 points). Derived pairs:
[`v3-dataset/v3-cap-pairs.csv`](v3-dataset/v3-cap-pairs.csv).
`score3` empty. No host / password fields.

### 6.1 Capability_4090

```text
Capability_4090 =
  C    ∥ HtoD     parallel     (confirms #51)
  C    ∥ DtoH     parallel     (new)
  HtoD ∥ HtoD     serial       (confirms #52)
  DtoH ∥ DtoH     serial       (new)
  HtoD ∥ DtoH     mixed        (new; not max, not sum)
  C    ∥ C        serial       (new; 16M degraded)
```

| Pair | 4M | 16M | 64M |
| ---- | -- | --- | --- |
| C ∥ HtoD | parallel (1.105 / 0.740) | parallel (1.031 / 0.555) | parallel (1.016 / 0.646) |
| C ∥ DtoH | parallel (1.111 / 0.734) | parallel (1.042 / 0.550) | parallel (1.015 / 0.655) |
| HtoD ∥ HtoD | serial (1.988 / 0.994) | serial (1.992 / 0.996) | serial (2.037 / 1.019) |
| DtoH ∥ DtoH | serial (1.987 / 0.994) | serial (1.996 / 0.998) | serial (1.999 / 0.999) |
| HtoD ∥ DtoH | mixed (1.453 / 0.742) | mixed (1.467 / 0.749) | mixed (1.468 / 0.749) |
| C ∥ C | serial (1.800 / 0.900) | serial (4.042 / 2.021) | serial (2.002 / 1.001) |

Cells are `par/max` / `par/sum`. `canOverlap=true` is not a
device-wide boolean.

### 6.2 Bidirectional communication

At every N:

```text
T(HtoD ∥ DtoH)  ≈  1.47 · max(T_HtoD, T_DtoH)
T(HtoD ∥ DtoH)  ≈  0.75 · (T_HtoD + T_DtoH)
```

So `sched.concurrent` on opposite-direction copies is **partial
duplex**, not `max` and not `sum`. Same-direction copies stay
`≈ sum`.

HtoD → event → DtoH versus HtoD → DtoH: delta 2–8 µs. The
explicit wait is real and small next to MB-scale copies.

### 6.3 Size curve / launch + bandwidth

Fit on sizes ≥ 1MB:

```text
T_htod ≈  9.41 µs  +  bytes / 25.25 GB/s
T_dtoh ≈  8.67 µs  +  bytes / 26.31 GB/s
```

1KB is ~5.2 µs (~0.20 GB/s). `Bytes/BW` without `T_launch`
misses the small-copy floor. Large pinned HtoD/DtoH on this
machine is ~25–26 GB/s (PCIe-class, not HBM).

### 6.4 Synchronization

Idle-stream inner-loop median:

```text
T_event    ≈  5.5 µs
T_stream   ≈  0.2 µs
T_device   ≈  0.4 µs
```

`C_synchronization` is a measurable host/device wait, on the
order of microseconds, not a copy-sized term.

### 6.5 Compute intensity (stand-in)

```text
SiLU k=32     4M / 16M / 64M :  332 / 2293 / 18588 µs
reduction     4M / 16M / 64M :   21 /  103 /   349 µs
matmul dim    256 / 512 / 1024:  15 /   52 /   343 µs
```

Elementwise and reduction stay memory-side. Tiled GEMM at
dim=1024 is the compute-side stand-in (~6 TFLOP/s, far below
4090 peak; not a cuBLAS claim). MLP / gated_mlp stay later.

C ∥ C at 16M was re-run and stayed ~4× one compute. That is
contention / degradation, not overlap. Do not turn it into a
Cost axiom in this increment.

### 6.6 What this is not

```text
Capability_4090  ≠  Cost v0.4
mixed HtoD∥DtoH  ≠  a new C_overlap formula
T_launch         ≠  a Score_3 rewrite
V3               ≠  claimed
```

A later Cost may consume this matrix. This layer only records
it.
