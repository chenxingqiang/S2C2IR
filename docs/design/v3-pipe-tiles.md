# V3 Pipeline Tiles Sanity Check (v0.1)

Status: **4090 evidence recorded**. Not Cost v0.4. Does
**not** change Cost, HB, `R`, Search, Transformation,
Pilot IR, A/B/C bodies, `--matched` / `--phase` / `--cap`
bodies, `--pipe` timed bodies, the frozen `#57` `tiles=8`
table, or Capability_4090. Baseline: `46aa592` (`#57`).
Protocol: `cfff554`. Dataset:
`docs/design/v3-dataset/v3-pipe-tiles.jsonl`.

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

## 6. RTX 4090 results (72 points → 12 slices)

Same 4090 / driver 570.124.06 / runtime 12080 as `#57`.
Records: [`v3-dataset/v3-pipe-tiles.jsonl`](v3-dataset/v3-pipe-tiles.jsonl).
Derived: [`v3-dataset/v3-pipe-tiles-slices.csv`](v3-dataset/v3-pipe-tiles-slices.csv).

72 points = 3 N × 4 tiles × (copy + 4 depths + compute@k).
The k=1 unit kernel is used only to choose `k` and is not
stored.

| N | tiles | r_tile | T(1) | T(2) | T(3) | T(4) | sp(2) | ideal | sat T(4)/T(2) |
| - | ----- | ------ | ---- | ---- | ---- | ---- | ----- | ----- | ------------- |
| 4M | 4 | 0.404 | 978 | 759 | 758 | 758 | 1.289 | 1.404 | 0.999 |
| 4M | 8 | 0.333 | 972 | 733 | 733 | 733 | 1.325 | 1.333 | 1.000 |
| 4M | 16 | 0.388 | 1072 | 751 | 752 | 752 | 1.428 | 1.388 | 1.001 |
| 4M | 32 | 0.467 | 1273 | 812 | 811 | 811 | 1.567 | 1.467 | 0.999 |
| 16M | 4 | 0.479 | 3968 | 3005 | 3002 | 3002 | 1.320 | 1.479 | 0.999 |
| 16M | 8 | 0.339 | 3612 | 2813 | 2812 | 2812 | 1.284 | 1.339 | 1.000 |
| 16M | 16 | 0.305 | 3559 | 2784 | 2783 | 2783 | 1.278 | 1.305 | 1.000 |
| 16M | 32 | 0.313 | 3686 | 2826 | 2822 | 2823 | 1.304 | 1.313 | 0.999 |
| 64M | 4 | 0.995 | 21233 | 13830 | 13778 | 13829 | 1.535 | 1.995 | 1.000 |
| 64M | 8 | 0.574 | 16539 | 11431 | 11464 | 11463 | 1.447 | 1.574 | 1.003 |
| 64M | 16 | 0.446 | 15479 | 10999 | 10997 | 10998 | 1.407 | 1.446 | 1.000 |
| 64M | 32 | 0.350 | 14422 | 10879 | 10891 | 10889 | 1.326 | 1.350 | 1.001 |

```text
T(2) ≈ T(3) ≈ T(4)          at every (N, tiles)
T(4) / T(2) ∈ [0.999, 1.003]
mean_sat = 1.000
```

So **depth=2 saturation is not a tiles=8 artifact**. Extra
residency still adds no measurable throughput under this
tested regime.

`tiles=8` reproduces `#57` within run noise (64M: T(2) =
11431 vs 11390, sat = 1.003 vs 1.004).

Two further, still local, observations:

1. **Not an r<1 artifact either.** At 64M / tiles=4 the
   tile ratio lands at `r ≈ 0.995` (pair ideal ≈ 2) and
   saturation is still 1.000.
2. **Fill/drain, not missing overlap, explains tiles=4.**
   Pair `ideal = (T_c+T_i)/max` is the infinite-tile
   ceiling. The finite-tile model is `T_ideal_pipe`.
   At 64M / tiles=4:

   ```text
   T(1) / T_ideal_pipe ≈ 21233 / 13334 = 1.592
   measured speedup(2)                 = 1.535
   ```

   `speedup(2) / pair-ideal` rises toward 1 as tiles grow
   (64M: 0.77 → 0.92 → 0.97 → 0.98). That is the
   fill/drain fraction shrinking. It is **not** “more
   tiles ⇒ more speedup”: at 64M, `speedup(2)` itself
   falls (1.535 → 1.326) because smaller tiles are more
   copy-heavy and pair-ideal falls with them.

At small N / tiles=32, one-tile `T_copy` is launch-heavy,
so `T_ideal_pipe` overestimates and `T(2)` can beat it.
That is a measurement-floor effect, not extra depth
gain. Do not FileCheck microseconds.

```text
No measurable gain from depth>2 under this tested regime
saturated@2  ≠  ∀ pipeline / ∀ GPU / ∀ C∥DMA
tiles sweep  ≠  Cost v0.4
V3           ≠  claimed
```
