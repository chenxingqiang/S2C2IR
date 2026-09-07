# V3 hidden_frac vs T_compute/T_copy (v0.1)

Status: **analysis of frozen calibration evidence**. Not Cost
v0.4. Does **not** change Cost, HB, `R`, Search,
Transformation, or the 48-point microseconds. Baseline:
`1eb264c` (`#53`). Table:
[`v3-dataset/v3-matched-calibration.csv`](v3-dataset/v3-matched-calibration.csv).

```text
Question     :  is hidden_frac = f(T_compute / T_copy)
                stable / monotonic / repeatable on this 4090?
hidden_frac>1  =  measurement-noise, not >100% overlap
Cost v0.4      ≠  opened
V3             ≠  claimed
```

---

## 1. Axis

Fit and rank against the hardware ratio, not raw `k`:

```text
r  =  T_compute / T_copy
```

`k` is only how the grid stepped compute. The same `k`
is a different `r` at 4M vs 64M.

```text
hidden_frac > 1  →  flag measurement-noise
```

That point is excluded from the clean / well-conditioned
summaries. It is not physical efficiency above 100%.

Well-conditioned:

```text
ok  and  0.2 < r < 4
```

Writer: `runtime/cuda/record_v3.py --analyze-ratio`.

---

## 2. This 4090 table

12 frozen slices. Two noise flags:

| N | k | r | hidden_frac | flag |
| - | - | -: | ----------: | ---- |
| 16M | 1 | 0.023 | 1.835 | measurement-noise |
| 16M | 8 | 0.208 | 1.052 | measurement-noise |

```text
ρ(r, hidden_frac)  all 12              0.081
ρ                  clean 10            0.571
ρ                  well-conditioned 7  0.054
clean inversions when pooled by r      4
```

Within `N`:

```text
4M    r: 0.027 → 1.07    hf: 0.56 → 0.88   (rises; more overhead)
16M   remaining clean    hf ≈ 0.99         (saturated)
64M   r: 0.05  → 3.50    hf: 0.94 → 0.97   (already high, then flat)
```

Pooled `f(r)` is **not stable**. `N` (absolute copy size /
launch overhead) still moves the point. On the
well-conditioned subset the rank correlation is ~0.

```text
f(r) = not-stable
```

---

## 3. Verdict

```text
Overlap direction     still holds (from #51 / #53)
hidden_frac = f(r)    not a single N-independent curve here
Cost v0.4             remains CLOSED
Score_3               still not a physical predictor
```

A later Cost term would need at least `r` **and** a size /
occupancy factor, or more devices. This grid is not enough
to replace `C_overlap` with a fitted `f(r)`.

---

## 4. Out of scope

```text
rewriting C_overlap / Score_3
editing the 48-point microseconds
claiming V3 pass
new T kind / Search
```
