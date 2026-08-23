# V3 4090 Resource / Capability Matrix (v0.1)

Status: **measurement campaign**. Not Cost v0.4. Does **not**
change Cost, HB, `R`, Search, Transformation, Pilot IR, A/B/C
bodies, or the frozen matched calibration table. Baseline:
`4baecc8` (`#54`).

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
| `docs/design/v3-dataset/` | 4090 records after the run |

Do not FileCheck microseconds. Do not FileCheck a Cost v0.4
rewrite.

---

## 6. Target matrix (fill after 4090)

```text
Capability_4090 =
  C  ∥ HtoD     #51  parallel (re-measure as cap-compute-htod)
  C  ∥ DtoH     pending
  HtoD ∥ HtoD   #52  serial   (re-measure as cap-htod-htod-par)
  DtoH ∥ DtoH   pending
  HtoD ∥ DtoH   pending
  C  ∥ C        pending
```

Plus `BW(size)`, `T_launch`, `T_sync`. This is calibration
evidence, not a Cost patch.
