# V3 Matched Overlap Calibration Evidence (v0.1)

Status: **calibration evidence frozen**. Not Cost v0.4. Does
**not** change Cost, HB, `R`, Search, Transformation, Pilot
IR, or A/B/C timed bodies. Baseline: `d07f849` (`#51`).

```text
Calibration evidence  ≠  Score_3 validation
Overlap direction     ≠  a physical C_overlap number
hidden_frac table     ≠  Cost v0.4
V3                    ≠  claimed
```

---

## 1. What is frozen

The 48-point 4090 matched-workload grid from `#51` is now
the fixed calibration record for:

```text
(N, k)  →  (T_copy, T_compute, T_seq, T_ovl, hidden_frac)
```

Remaining work on every slice:

```text
1 × HtoD(H) + k × SiLU(D)     D ≠ H
seq : HtoD then SiLU
ovl : HtoD ∥ SiLU
```

Records: [`v3-dataset/v3-matched.{jsonl,csv}`](v3-dataset/).
Derived table: [`v3-dataset/v3-matched-calibration.csv`](v3-dataset/v3-matched-calibration.csv).
Writer: `runtime/cuda/record_v3.py --calibrate`.

Do **not** edit those microseconds in place. A later machine
or grid is a new file.

---

## 2. Two independent conclusions

### Semantics (frozen here)

```text
Compute ∥ one HtoD produces real wall-clock overlap
on this RTX 4090 matched grid.
```

```text
T_seq  ≈  T_copy + T_compute
T_ovl  ≈  max(T_copy, T_compute)
mean hidden_frac ≈ 0.982
well-conditioned hidden_frac ∈ [0.88, 0.99]
```

The `#49/#50` `B < A` Score_3 vs latency mismatch is a
stand-in confound (unequal remaining work, extra HtoD).
It is **not** evidence that overlap semantics are wrong.

### Cost (still open as a question, closed as a patch)

```text
Score_3 is not hardware-validated.
C_overlap is a semantic upper-bound credit, not a
fitted f(T_compute / T_copy).
Cost v0.4 remains CLOSED.
```

---

## 3. Next question (not a Cost patch)

With the table frozen, a later analysis may ask:

```text
hidden_frac  =  f(T_compute / T_copy)   ?
```

That analysis is [`v3-hidden-frac-ratio.md`](v3-hidden-frac-ratio.md).
It does not open Cost v0.4.

If `T_ovl ≈ max(T_copy, T_compute)` stays stable across
more devices, `C_overlap` can stay a “available parallelism”
credit. If it depends on copy-engine occupancy, bandwidth,
or contention, a later Cost revision would need that
function. That decision is **not** made here.

---

## 4. Out of scope

```text
rewriting C_overlap / Score_3
new T kind / Search
claiming V3 pass
editing the 48-point microseconds
```
