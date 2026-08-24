# V3 Pipeline Depth × Double Buffer (v0.1)

Status: **measurement campaign**. Not Cost v0.4. Does **not**
change Cost, HB, `R`, Search, Transformation, Pilot IR, A/B/C
bodies, `--matched` / `--phase` / `--cap` bodies, or the
frozen Capability_4090 / phase tables. Baseline: `5ddcc3a`
(`#56`).

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
| `docs/design/v3-dataset/` | 4090 records after the run |
