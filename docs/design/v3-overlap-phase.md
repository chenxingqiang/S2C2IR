# V3 Overlap Phase Diagram (v0.1)

Status: **measurement campaign**. Not Cost v0.4. Does **not**
change Cost, HB, `R`, Search, Transformation, Pilot IR, A/B/C
bodies, `--matched` bodies, or the frozen Capability_4090
table. Baseline: `0798aed` (`#55`).

```text
Phase diagram     ≠  a Cost axiom
--phase           ≠  a new Pilot func
Capability pair   ≠  a continuous phase
V3                ≠  claimed
```

---

## 1. Why this layer

`#55` froze a discrete pair matrix:

```text
Capability_4090(pair) ∈ {parallel, serial, mixed}
```

That is a verdict, not a scheduler surface. `#54` already
showed `hidden_frac = f(r)` is not N-independent. This
increment measures the missing continuous axes:

```text
r = T_compute / T_copy
N = payload size
```

on **one** pair only:

```text
Compute ∥ HtoD
```

Same remaining work as `--matched` (`#51`):

```text
1× HtoD(H) + k× SiLU(D)    D ≠ H
```

`--phase` reprints those four arms as `phase-*`. It does not
change the timed bodies.

This diagram is **not** a claim about all compute, and not
about HtoD∥DtoH. `#55` already warned that `C∥C = serial` is
this SiLU arm under the measured resource, not
`∀ C1,C2`. The same discipline applies here:

```text
Phase(C ∥ HtoD, r, N)  ≠  Phase(device)
```

---

## 2. Grid

```text
N         ∈ {4M, 16M, 64M}
r_target  ∈ {0.01, 0.03, 0.1, 0.3, 1, 3, 10, 30}
```

Per N, measure `T_copy` and `T_unit = T_compute(k=1)`, then:

```text
k = clamp(round(r_target · T_copy / T_unit), 1, 4096)
```

`k=1` is the compute floor. Large N cannot hit r=0.01.
Records store `k`; analysis reports `r_achieved`. Duplicate
`k` values are run once.

Arms: `phase-copy` (once per N), then per `(N,k)`:
`phase-compute`, `phase-seq`, `phase-ovl`.

---

## 3. Metrics (not Cost)

```text
r            = T_compute / T_copy
ovl / max    = T_ovl / max(T_copy, T_compute)
ovl / sum    = T_ovl / (T_copy + T_compute)
hidden_frac  = (T_seq − T_ovl) / min(T_copy, T_compute)
```

Dominance (by `r_achieved`):

```text
r < 0.3   copy-dominated
0.3 ≤ r ≤ 3   balanced
r > 3     compute-dominated
```

Overlap class (measurement, not a Cost axiom):

```text
hid_short  =  ovl/max ≤ 1.15
near_sum   =  ovl/sum ≥ 0.90

hid_short ∧ ¬near_sum   →  parallel
near_sum  ∧ ¬hid_short  →  serial
hid_short ∧  near_sum   →  underdetermined
else                    →  mixed
```

`underdetermined` is the extreme-`r` case: `max` and `sum`
are too close to tell apart. That is `#54`'s lesson, not a
device-wide serial verdict.

Expected cartoon:

```text
compute-dominated
      ↑
      │       overlap
      │     /
      │    /
      │   /
      └────────────→ communication-dominated
```

Do not replace `C_overlap` with a fitted `f(r,N)`.

---

## 4. Out of this increment

```text
stream-count / pipeline-depth / double-buffering
pageable vs pinned
HtoD∥DtoH or C∥C phase surfaces
rewriting Capability_4090 or Cost
claiming V3
```

---

## 5. Files

| Path | Role |
| ---- | ---- |
| `runtime/cuda/s2c2_cuda_adapter.cu` | `--phase=` (same bodies as `--matched`) |
| `tools/s2c2-cuda-adapter/` | host `--dry-run --phase` |
| `runtime/cuda/record_v3.py` | `--phase-sweep` / `--analyze-phase` |
| `docs/design/v3-dataset/` | 4090 records after the run |

Do not FileCheck microseconds.
