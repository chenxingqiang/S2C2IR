# V3 Matched-Workload Overlap Control (v0.1)

Status: **calibration evidence frozen** after `#51`
(`d07f849`). See [`v3-matched-calibration.md`](v3-matched-calibration.md).
Not Cost v0.4. Does **not** change Cost, HB, `R`, Search,
Transformation, Pilot IR, or the frozen A/B/C timed bodies.
Baseline: `b10087c` (`#49`). Companion A/B/C ranks: `#50`.

```text
Matched remaining work  ≠  a new Pilot func
--matched               ≠  a Cost axiom
score3                  ≠  applicable on these records
V3                      ≠  claimed
```

---

## 1. Why this experiment

The 36-point 4090 grid showed:

```text
Score_3 :  B < A < C
Latency :  A first on every slice
B < A   :  0 / 12
```

`#50` already says that same-slice A vs B is **not** “same
remaining work, different schedule”:

| case | provisioned=1 timed body |
| ---- | ------------------------ |
| A | SiLU only |
| B | SiLU ∥ HtoD |

So `C_overlap` cannot be judged from A/B/C ranks. This layer
times **one HtoD + k×SiLU** twice: sequential vs overlapped.

---

## 2. Remaining work (identical on both arms)

```text
1 × HtoD of N floats   host_pinned → device buffer H
k × SiLU of N floats   device buffer D  (already resident)
```

`D` and `H` are **different** buffers. Overlap is therefore
legal (no write–write race). This is the Concurrent
compute ∥ comm shape, not B's two-HtoD stand-in.

| arm | Timed body |
| --- | ---------- |
| `seq` | HtoD(H) then SiLU×k(D) on one stream |
| `ovl` | SiLU×k(D) ∥ HtoD(H) on two streams |
| `copy` | HtoD(H) only |
| `compute` | SiLU×k(D) only |

`copy` and `compute` are calibration, not a third schedule.

```text
T_seq      ≈  T_copy + T_compute     (sanity)
ideal wall =  max(T_copy, T_compute)
ideal gain =  min(T_copy, T_compute)
gain       =  T_seq − T_ovl
hidden_frac = gain / ideal_gain
```

`hidden_frac → 1` means the shorter side is hidden.
`hidden_frac → 0` means the schedule credit is not realized.

Sweep `k` so `T_compute / T_copy` crosses `≪ 1`, `~1`, `≫ 1`.
On the existing 4090 slice (N=16M, k=1) that ratio is
`~66 / ~2600`. `k ∈ {1, 8, 32, 64}` is the first grid.

---

## 3. What does not change

```text
runA / runB / runC
Score_3 130 / 128 / 163
36-point A/B/C schema (FIELDS unchanged)
C_overlap / Cost v0.1–v0.3
Pilot IR
```

`--matched` is ignored unless requested. Default A/B/C
behavior is bit-identical to `b10087c`.

Matched records reuse the frozen metadata FIELDS. `case` is
`matched-seq` / `matched-ovl` / `matched-copy` /
`matched-compute`. `score3` is empty (not a Score_3 case).
`provisioned` is `1` (D is filled before the timer).
Sources stay:

```text
driver_version  ← nvidia-smi
nvcc_version    ← nvcc --version
cuda_runtime    ← cudaRuntimeGetVersion()
```

No host, account, password, or IP.

---

## 4. Grid

```text
N     ∈ {4M, 16M, 64M} = {4194304, 16777216, 67108864}
k     ∈ {1, 8, 32, 64}
arm   ∈ {seq, ovl, copy, compute}
```

```text
3 × 4 × 4  =  48 GPU points
```

Device is GPU only. This is not a CPU experiment.

---

## 5. How to read a result

This experiment can support **one** of these later claims,
and only after numbers exist:

1. `hidden_frac` stays near 0 across the ratio sweep
   → hardware does not give the free overlap `C_overlap`
   assumes; a later Cost revision would need contention.
2. `hidden_frac` rises toward 1 as `T_compute ~ T_copy`
   → the A/B mismatch was a stand-in artifact; do not
   rewrite `C_overlap` from A/B/C ranks.
3. Mixed → credit is ratio-dependent; still not Cost v0.4
   until a model of that dependence exists.

```text
V3           still not claimed
Cost v0.4    still not opened
```

---

## 6. Files

| Path | Role |
| ---- | ---- |
| `runtime/cuda/s2c2_cuda_adapter.cu` | `--matched=seq\|ovl\|copy\|compute\|all` |
| `tools/s2c2-cuda-adapter/` | host `--dry-run --matched` protocol |
| `runtime/cuda/record_v3.py` | `--matched-sweep` / `--analyze-matched` |
| `runtime/cuda/sweep_matched.sh` | wrapper |
| `test/Pilot/s2c2-v3-matched-overlap.mlir` | protocol FileCheck |
| [`v3-dataset/v3-matched.jsonl`](v3-dataset/v3-matched.jsonl) | 48-point 4090 records |

Do not FileCheck microseconds.

---

## 7. One RTX 4090 matched sweep (48 points, not V3)

Files: [`v3-dataset/v3-matched.{jsonl,csv}`](v3-dataset/).
Median of 21 timed reps, warmup 5. Binary `315389e`.
`score3` is empty. A/B/C bodies were not run.

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

| N | k | seq | ovl | copy | compute | ratio | hidden | ovl/max |
| - | - | --: | --: | ---: | ------: | ----: | -----: | ------: |
| 4M | 1 | 686 | 676 | 671 | 18 | 0.027 | 0.560 | 1.008 |
| 4M | 8 | 766 | 689 | 671 | 96 | 0.144 | 0.797 | 1.027 |
| 4M | 32 | 1032 | 736 | 671 | 363 | 0.540 | 0.816 | 1.098 |
| 4M | 64 | 1390 | 800 | 671 | 720 | 1.073 | 0.880 | 1.111 |
| 16M | 1 | 2785 | 2671 | 2668 | 63 | 0.023 | 1.835 | 1.001 |
| 16M | 8 | 3274 | 2692 | 2663 | 553 | 0.208 | 1.052 | 1.011 |
| 16M | 32 | 4954 | 2749 | 2664 | 2231 | 0.837 | 0.988 | 1.032 |
| 16M | 64 | 7193 | 4542 | 2666 | 4469 | 1.676 | 0.995 | 1.016 |
| 64M | 1 | 11159 | 10656 | 10638 | 534 | 0.050 | 0.942 | 1.002 |
| 64M | 8 | 15232 | 10700 | 10637 | 4608 | 0.433 | 0.984 | 1.006 |
| 64M | 32 | 29205 | 18884 | 10629 | 18577 | 1.748 | 0.971 | 1.016 |
| 64M | 64 | 47837 | 37514 | 10627 | 37208 | 3.501 | 0.971 | 1.008 |

```text
slices                 12
mean hidden_frac       0.982
seq ≈ copy + compute   (seq_over_sum ≈ 1.00)
ovl ≈ max(copy,compute)
```

`hidden_frac > 1` on N=16M, k=1 is timer/additivity noise:
`T_compute` is ~2% of `T_copy`. Well-conditioned slices
(`0.2 < T_compute/T_copy < 4`) sit at `hidden_frac ≈ 0.88–0.99`.

This is reading **2** of §5: matched compute ∥ one HtoD
**does** hide the shorter side on this GPU. The A/B Score_3
vs latency mismatch on the 36-point grid is a **stand-in
artifact** (unequal remaining work, and B's two-HtoD
contention), not a refutation of `C_overlap`'s direction.

```text
Matched 1×HtoD ∥ k×SiLU   overlap is real on this 4090
Two concurrent HtoDs      still not modeled (B stand-in)
Score_3                   still not a physical predictor
V3                        not claimed
Cost v0.4                 not opened
```

---

## 8. Out of scope

```text
rewriting C_overlap / Score_3
changing A/B/C timed bodies
new T kind / Search
claiming V3 pass
real SSD
```
