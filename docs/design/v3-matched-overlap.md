# V3 Matched-Workload Overlap Control (v0.1)

Status: **measurement experiment**. Not Cost v0.4. Does **not**
change Cost, HB, `R`, Search, Transformation, Pilot IR, or the
frozen A/B/C timed bodies. Baseline: `b10087c` (`#49`).
Companion analysis of the 36-point A/B/C grid: `#50`.

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

None of those claims is made in this document.

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
| `docs/design/v3-dataset/` | later 4090 records, if collected |

Do not FileCheck microseconds.

---

## 7. Out of scope

```text
rewriting C_overlap / Score_3
changing A/B/C timed bodies
new T kind / Search
claiming V3 pass
real SSD
```
