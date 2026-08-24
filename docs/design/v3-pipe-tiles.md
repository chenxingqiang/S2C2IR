# V3 Pipeline Tiles Sanity Check (v0.1)

Status: **protocol only**. 4090 not yet recorded. Not Cost
v0.4. Does **not** change Cost, HB, `R`, Search,
Transformation, Pilot IR, A/B/C bodies, `--matched` /
`--phase` / `--cap` bodies, `--pipe` timed bodies, the
frozen `#57` `tiles=8` table, or Capability_4090. Baseline:
`46aa592` (`#57`).

```text
tiles sweep        ≠  a Cost axiom
--pipe-tiles       ≠  a new Pilot func
--pipe default     ≠  changed (still tiles=8)
depth*=N_resource  ≠  claimed
V3                 ≠  claimed
```

---

## 1. Why this layer

`#57` showed, on this SiLU C∥HtoD arm only:

```text
tiles = 8
T(2) ≈ T(3) ≈ T(4)
T(4) / T(2) ∈ [1.000, 1.004]
```

That saturation could still be a **tiles=8 fill/drain
artifact**: eight tiles is enough for a 2-resource pipeline
to look steady, but not enough to prove the plateau is
independent of tile count.

This increment asks one question:

```text
Is depth=2 saturation stable across tiles ∈ {4, 8, 16, 32}?
```

Not “all GPU pipelines are double-buffered.” Same pair,
same depths, same 4090 SiLU arm. Only the tile count moves.

---

## 2. Grid

```text
pair    = C ∥ HtoD
N       ∈ {4M, 16M, 64M}
tiles   ∈ {4, 8, 16, 32}
depth   ∈ {1, 2, 3, 4}
```

Tile length is `N / tiles`. Every listed `N` divides every
listed `tiles`. `k` is chosen **per (N, tiles)** so tile
`r ≈ 1` from `T_compute(k=1)`, same policy as `#57`.
Achieved `r_tile` may again land below 1 because launch is
amortized; do not read that as “unbalanced failure.”

Schedule is the `#57` event pipeline. `--pipe` print names
stay `pipe-d1`…; the recorder **retags** after parse:

```text
pipe-copy     →  pipe-t{T}-copy
pipe-compute  →  pipe-t{T}-compute
pipe-d1       →  pipe-t{T}-d1
…
```

Frozen metadata FIELDS have no `tiles` column. Case names
carry the tiles count. `#57` `--analyze-pipe` still groups
the untagged `pipe-d*` rows and still assumes `tiles=8`.

Ideal 2-resource warm-up + steady-state:

```text
T_ideal_pipe = T_c + T_i + (tiles − 1) · max(T_c, T_i)
```

For `tiles=8` this is the `#57` formula.

---

## 3. Metrics (not Cost)

```text
T_copy, T_compute     one tile at the chosen k
T(d)                  full tiles-run at depth d
speedup(d)            T(1) / T(d)
ideal                 (T_c + T_i) / max(T_c, T_i)
T_ideal_pipe          as above
saturated             T(4) / T(2) ≈ 1
```

What would support “not a tiles=8 artifact”:

```text
T(2) ≈ T(3) ≈ T(4)     at every tiles in the set
T(4) / T(2) ≈ 1
T(2) ≈ T_ideal_pipe
```

A secondary, non-blocking observation:

```text
fill/drain shrinks as tiles grow
speedup(2) should approach ideal at tiles=32
more than at tiles=4
```

That is a shape check, not a Cost rewrite.

---

## 4. Out of this increment

```text
3-stage HtoD → Compute → DtoH
HtoD∥DtoH / C∥C / other pairs
rewriting C_overlap / Capability_4090 / Cost v0.4
changing --pipe default tiles=8
claiming depth* = N_resource as a law
claiming V3
```

---

## 5. Files

| Path | Role |
| ---- | ---- |
| `tools/s2c2-cuda-adapter/` | host `--dry-run --pipe-tiles` |
| `runtime/cuda/record_v3.py` | `--pipe-tiles-sweep` / `--analyze-pipe-tiles` |
| `runtime/cuda/sweep_pipe_tiles.sh` | 4090 driver |
| `docs/design/v3-dataset/v3-pipe-tiles.jsonl` | 72-point 4090 records (after sweep) |

`--pipe` timed CUDA bodies are unchanged. Host `--dry-run
--pipe` still lists `tiles=8`.

---

## 6. RTX 4090 results

Pending measurement. Expected 3 N × 4 tiles ×
(copy + 4 depths + compute@k) = **72** points. The k=1
unit kernel is used only to choose `k` and is not stored.

Do not FileCheck microseconds.
