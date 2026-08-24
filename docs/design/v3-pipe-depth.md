# V3 Pipeline Depth × Double Buffer (v0.1)

Status: **4090 evidence recorded**. Not Cost v0.4. Does **not**
change Cost, HB, `R`, Search, Transformation, Pilot IR, A/B/C
bodies, `--matched` / `--phase` / `--cap` bodies, or the
frozen Capability_4090 / phase tables. Baseline: `5ddcc3a`
(`#56`). Dataset: `4de48c7`.

```text
Pipeline depth     ≠  a Cost axiom
--pipe             ≠  a new Pilot func
Double buffer      ≠  a free search over schedules
V3                 ≠  claimed
```

---

## 1. Why this layer

`#56` showed, on this SiLU arm only:

```text
Phase(C ∥ HtoD, r, N):  T_ovl ≈ max(T_c, T_i)
```

when the two sides are comparable. That is a **single-shot**
pair. This increment asks whether that max-like overlap
becomes multi-tile throughput:

```text
T_pipeline(depth)
speedup(depth) = T(depth=1) / T(depth)
```

Underlying pair stays **C ∥ HtoD**. Not HtoD∥DtoH, not C∥C,
not a 3-stage HtoD→Compute→DtoH search.

Double buffering is `depth=2`. `depth=3,4` only add
buffers on the same 2-stage pair. If the pair is truly
2-resource max-like, extra buffers should **saturate**
at 2:

```text
T(3) ≈ T(4) ≈ T(2)
speedup → (T_copy + T_compute) / max(T_copy, T_compute)  ≤  2
```

---

## 2. Schedule

Total payload `N`, frozen `tiles=8`, tile length `N/8`.
Per tile remaining work is the matched pair:

```text
1× HtoD(tile i) + k× SiLU(tile i)
```

`k` is chosen so tile-level `r ≈ 1` (balanced), where
single-shot overlap was identifiable.

Event pipeline, `depth` device buffers:

```text
for i in 0..tiles-1:
  if i >= depth:   wait compute(i − depth)   # buffer free
  HtoD(i) → buf[i % depth]
  wait that HtoD
  Compute(i) on buf[i % depth]
```

```text
depth=1   one buffer; HtoD then Compute; no overlap
depth=2   double buffer; HtoD(i+1) ∥ Compute(i)
depth=3,4 extra residency; same two resources
```

Do not FileCheck microseconds.

---

## 3. Metrics (not Cost)

```text
T_copy, T_compute     one tile
T(d)                  full 8-tile run at depth d
speedup(d)            T(1) / T(d)
ideal                 (T_c + T_i) / max(T_c, T_i)
T_ideal_pipe          T_c + T_i + 7 · max(T_c, T_i)
saturated             T(4) / T(2) ≈ 1
```

---

## 4. Out of this increment

```text
3-stage HtoD → Compute → DtoH
stream-count / pageable / gated_mlp
rewriting C_overlap / Capability_4090 / Cost v0.4
claiming V3
```

---

## 5. Files

| Path | Role |
| ---- | ---- |
| `runtime/cuda/s2c2_cuda_adapter.cu` | `--pipe=` |
| `tools/s2c2-cuda-adapter/` | host `--dry-run --pipe` |
| `runtime/cuda/record_v3.py` | `--pipe-sweep` / `--analyze-pipe` |
| `docs/design/v3-dataset/v3-pipe.jsonl` | 18-point 4090 records |

---

## 6. RTX 4090 results (18 points → 3 slices)

Same 4090 / driver 570.124.06 / runtime 12080 as `#56`.
Records: [`v3-dataset/v3-pipe.jsonl`](v3-dataset/v3-pipe.jsonl).
Derived: [`v3-dataset/v3-pipe-slices.csv`](v3-dataset/v3-pipe-slices.csv).

Tile `k` is chosen from `T_compute(k=1)`, so achieved tile
`r` is 0.38–0.54 (copy-heavier than 1). Launch in the unit
kernel is amortized. That still leaves a measurable
`max` vs `sum` gap.

| N | r_tile | T(1) | T(2) | T(3) | T(4) | sp(2) | ideal | sat T(4)/T(2) |
| - | ------ | ---- | ---- | ---- | ---- | ----- | ----- | ------------- |
| 4M | 0.377 | 994 | 734 | 734 | 734 | 1.354 | 1.377 | 1.000 |
| 16M | 0.390 | 3759 | 2827 | 2826 | 2830 | 1.330 | 1.390 | 1.001 |
| 64M | 0.542 | 16449 | 11390 | 11423 | 11431 | 1.444 | 1.542 | 1.004 |

```text
T(2) ≈ T(3) ≈ T(4)
speedup(2) ≈ ideal = (T_c + T_i) / max(T_c, T_i)
T(2) ≈ T_ideal_pipe
```

So **single-shot max-like C∥HtoD does convert** into an
8-tile pipeline, and **saturates at double buffer**. Extra
residency (`depth=3,4`) does not raise throughput on this
2-resource pair.

This is still this SiLU arm only. Not a 3-stage
prefetch→compute→writeback claim, and not Cost v0.4.

```text
T_pipeline(d)  ≠  a Score_3 rewrite
saturated@2    ≠  ∀ pipeline
V3             ≠  claimed
```
