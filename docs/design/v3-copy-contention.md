# V3 Two-HtoD Copy Contention (v0.1)

Status: **measurement experiment**. Not Cost v0.4. Does **not**
change Cost, HB, `R`, Search, Transformation, Pilot IR, A/B/C
bodies, or the matched-overlap arms. Baseline: `265e6f8` (`#51`).

```text
Two HtoDs     ≠  a new Pilot func
--contend     ≠  a Cost axiom
score3        ≠  applicable on these records
V3            ≠  claimed
```

---

## 1. Why this experiment

Matched overlap (`#51`) showed:

```text
1×HtoD ∥ k×SiLU   hides the shorter side on this 4090
```

B's stand-in is a different pair: **two HostToDevice copies**
(compute-path provisioning + IR comm), same pinned source.
Cost scores B as Compute∥IO and gives overlap credit. Hardware
may serialize the two copies on one copy/memory path.

This layer times **only the copies**.

---

## 2. Remaining work

```text
2 × HtoD of N floats
```

| arm | Timed body |
| --- | ---------- |
| `one` | HtoD `ssd → hbm` |
| `seq` | HtoD `ssd → hbm` then `ssd → scratch` (one stream) |
| `par` | those two HtoDs on two streams (B's copy pair) |
| `par-split` | HtoD `ssd → hbm` ∥ `ssd2 → scratch` (two host buffers) |

`par` is B's adapter copies without SiLU. `par-split` asks
whether the shared host pointer is the bottleneck.

```text
serialize_frac = (T_par − T_one) / T_one
par_over_seq   = T_par / T_seq
```

`serialize_frac → 1` and `par_over_seq → 1` means the second
HtoD pays a full extra copy. `serialize_frac → 0` means two
HtoDs run free.

`k` is unused. `provisioned` is `1` (timer is exactly the
named copies). `score3` is empty.

---

## 3. What does not change

```text
runA / runB / runC
--matched arms
Score_3 130 / 128 / 163
36-point and 48-point schemas
C_overlap / Cost v0.1–v0.3
```

Sources stay driver=`nvidia-smi`, nvcc=`nvcc`,
runtime=`cudaRuntimeGetVersion()`. No host, account,
password, or IP.

---

## 4. Grid

```text
N    ∈ {4M, 16M, 64M}
arm  ∈ {one, seq, par, par-split}
```

```text
3 × 4  =  12 GPU points
```

---

## 5. How to read a result

1. `T_par ≈ T_seq ≈ 2 · T_one`
   → one copy path; B's extra HtoD is not free. Do not
   rewrite `C_overlap` (that credit is Compute∥IO). A later
   model of **copy-engine occupancy** would be a different
   term.
2. `T_par ≈ T_one` and `T_par-split ≈ T_one`
   → two HtoDs really parallel; B's 2× latency was something
   else.
3. `T_par ≈ 2 · T_one` but `T_par-split ≈ T_one`
   → shared host buffer, not the device copy engine.

None of those is a Cost v0.4 patch.

```text
V3           still not claimed
Cost v0.4    still not opened
```

---

## 6. Files

| Path | Role |
| ---- | ---- |
| `runtime/cuda/s2c2_cuda_adapter.cu` | `--contend=one\|seq\|par\|par-split\|all` |
| `tools/s2c2-cuda-adapter/` | host `--dry-run --contend` |
| `runtime/cuda/record_v3.py` | `--contend-sweep` / `--analyze-contend` |
| `test/Pilot/s2c2-v3-copy-contention.mlir` | protocol FileCheck |
| [`v3-dataset/v3-contend.jsonl`](v3-dataset/v3-contend.jsonl) | 12-point 4090 records |

Do not FileCheck microseconds.

---

## 7. One RTX 4090 contention sweep (12 points, not V3)

Files: [`v3-dataset/v3-contend.{jsonl,csv}`](v3-dataset/).
Median of 21 timed reps, warmup 5. Binary `fec1cb5`.
`score3` is empty. A/B/C and `--matched` were not run.

Hardware snapshot (not a lock):

```text
gpu_model        NVIDIA GeForce RTX 4090
gpu_memory       24564
driver_version   570.124.06
cuda_runtime     12080
nvcc_version     release 12.8, V12.8.61
power_mode       limit_w=450.00
clock_state      pre-sweep snapshot
```

| N | one | seq | par | par-split | seq/2one | par/seq | serialize |
| - | --: | --: | --: | --------: | -------: | ------: | --------: |
| 4M | 675 | 1340 | 1340 | 1340 | 0.993 | 1.000 | 0.986 |
| 16M | 2669 | 5325 | 5327 | 5327 | 0.998 | 1.000 | 0.996 |
| 64M | 10632 | 21268 | 21259 | 21821 | 1.000 | 1.000 | 1.000 |

```text
slices                 3
mean serialize_frac    0.994
T_par ≈ T_seq ≈ 2 · T_one
T_par-split ≈ 2 · T_one
```

This is reading **1** of §5: two HtoDs share one copy path.
Splitting the host buffer does not free the second copy, so
the bottleneck is not the shared pinned pointer.

Together with `#51`:

```text
Compute ∥ 1×HtoD     hidden_frac ≈ 1     (overlap is real)
2×HtoD  ∥ each other serialize_frac ≈ 1  (copies are not free)
```

B's Score_3 credit is Compute∥IO. Hardware pays a second
HtoD in the stand-in. That is **copy-engine occupancy**, not
a reason to invert `C_overlap`.

```text
V3           not claimed
Cost v0.4    not opened
```

---

## 8. Out of scope

```text
rewriting C_overlap / Score_3
changing A/B/C or --matched
new T kind / Search
claiming V3 pass
real SSD
```
