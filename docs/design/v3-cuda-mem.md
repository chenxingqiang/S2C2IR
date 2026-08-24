# CUDA Validation — Pinned vs Pageable (V2 P0)

Status: **4090 evidence recorded**. Not Cost v0.4. Does
**not** change Cost, HB axioms, `R`, Search,
Transformation, Pilot IR, A/B/C bodies, `--matched` /
`--phase` / `--cap` / `--pipe` bodies, V1 `--cuda-val=p0`
timed bodies, or S^2C^2 Semantics. Baseline: `e44d577`
(`#60`). Protocol tree: `616cca2`.

```text
Host residency     !=  a Cost axiom
--cuda-val-mem     !=  a new Pilot func
stor.space<host>   !=  one CUDA realization
pageable HtoD      !=  a Schedule rewrite
V3                 !=  claimed
```

---

## 1. Why this layer

`#60` showed that the **same** S^2C^2 Concurrent shape
(`C || HtoD`) is max-like on named nonblocking streams and
sum-like on the legacy NULL stream. Extra HB came from the
**stream realization**, not from S^2C^2.

This increment freezes the stream policy that *can* overlap
and asks whether **host residency** still changes the
effective Communication / Overlap capability:

```text
same S^2C^2 transfer
+
same named nonblocking streams
+
different host residency
        |
        v
different effective async / overlap?
```

Two different questions, kept separate:

```text
1. Communication rate:   T_pageable / T_pinned  ?
2. Extra HB / overlap:   does pageable serialize C || copy?
```

`stor.space<host>` cannot mean "any host buffer" if (1) is
large. It would further decide overlap realization if (2)
is a serial flip. A bandwidth-only gap without a serial
flip is reported, but is not by itself extra-HB.

---

## 2. Grid

Streams stay **named nonblocking** (the `#60` cell that
was parallel). N in {4M, 16M, 64M}. `k` is chosen from
`T_htod(pinned)` and `T_compute(k=1)` so `r ~ 1`, same
policy as V1. All arms share that `k` (same remaining
compute work).

```text
               pinned              pageable
HtoD           val-htod-pinned     val-htod-pageable
DtoH           val-dtoh-pinned     val-dtoh-pageable
C || HtoD      val-ovl-htod-pin    val-ovl-htod-page
C || DtoH      val-ovl-dtoh-pin    val-ovl-dtoh-page
Compute        val-compute-mem     (device only, once)
```

Pinned host: `cudaHostAlloc`. Pageable host: `malloc`.
Device buffers and the two streams do not change.

Remaining work for overlap cells:

```text
C || HtoD :  k x SiLU(D)  ||  1 x HtoD(H -> D')     D != D'
C || DtoH :  k x SiLU(D)  ||  1 x DtoH(D' -> H)
```

Correctness is gated (`correct=0` exits 3), same `SiLU^k`
rule as `#60`. Timing uses the frozen `#55` classifier.
Do not FileCheck microseconds.

`--cuda-val-mem` is mutually exclusive with `--cuda-val` /
`--matched` / `--phase` / `--cap` / `--pipe`. V1 timed
bodies stay untouched.

`extra_hb = pageable-host` is a **realization
classification** from observed *serial* extra time, not a
reconstructed CUDA HB graph. Phrase as:

> observed extra serialization consistent with pageable-host
> staging / implicit synchronization

A `#55` mixed verdict with `ovl/max <= 1.15` is still
max-like. That gray zone is r-unbalance from a slower
pageable copy, not extra HB.

What would count as the Storage x Comm extra-HB
counterexample:

```text
pinned   C||HtoD  ->  parallel
pageable C||HtoD  ->  serial     (ovl/sum >= 0.90)
```

and/or the same serial flip on C||DtoH.

---

## 3. 4090 result (27 points -> 12 slices)

All arms `correct=1`. Same remaining compute `k` per N.
Pinned C||HtoD / C||DtoH stay **parallel** at all 3 N
(confirms `#60` named). Pageable copies are 2-3x slower.
Pageable overlap stays **max-like** (`T_ovl ~ T_copy`);
compute is still hidden under the slower copy.

| N | pair | res | k | r | copy | compute | ovl | ovl/max | ovl/sum | verdict |
| - | ---- | --- | - | - | ---- | ------- | --- | ------- | ------- | ------- |
| 4M | C||HtoD | pin | 31 | 0.528 | 671 | 354 | 734 | 1.094 | 0.717 | parallel |
| 4M | C||HtoD | page | 31 | 0.276 | 1280 | 354 | 1316 | 1.028 | 0.806 | mixed |
| 4M | C||DtoH | pin | 31 | 0.545 | 649 | 354 | 713 | 1.098 | 0.711 | parallel |
| 4M | C||DtoH | page | 31 | 0.186 | 1898 | 354 | 1958 | 1.032 | 0.869 | mixed |
| 16M | C||HtoD | pin | 20 | 0.548 | 2660 | 1457 | 2718 | 1.022 | 0.660 | parallel |
| 16M | C||HtoD | page | 20 | 0.236 | 6162 | 1457 | 6261 | 1.016 | 0.822 | mixed |
| 16M | C||DtoH | pin | 20 | 0.568 | 2566 | 1457 | 2700 | 1.052 | 0.671 | parallel |
| 16M | C||DtoH | page | 20 | 0.210 | 6935 | 1457 | 6990 | 1.008 | 0.833 | mixed |
| 64M | C||HtoD | pin | 20 | 1.092 | 10620 | 11602 | 11919 | 1.027 | 0.536 | parallel |
| 64M | C||HtoD | page | 20 | 0.468 | 24815 | 11602 | 24777 | 0.998 | 0.680 | parallel |
| 64M | C||DtoH | pin | 20 | 1.134 | 10233 | 11602 | 11974 | 1.032 | 0.548 | parallel |
| 64M | C||DtoH | page | 20 | 0.378 | 30687 | 11602 | 30695 | 1.000 | 0.726 | parallel |

```text
bandwidth HtoD page/pin :  1.908 / 2.317 / 2.337
bandwidth DtoH page/pin :  2.923 / 2.702 / 2.999
counterexamples         :  0 / 6
max-like-unbalanced     :  4     (4M + 16M, both pairs)
bandwidth-only          :  2     (64M, both pairs)
extra_hb                :  none
```

The four mixed cells have `ovl/max ~ 1.02` and
`ovl/sum ~ 1/(1+r)`. That is the `#55` gray zone from a
copy-dominated `r`, not `T_ovl ~ sum`.

```text
Communication rate  =  f(residency, direction, size)
C || copy           stays max-like on named streams
                    for both pinned and pageable
HB_pageable \ HB_S^2C^2  =  empty   (this regime)
HB_default  \ HB_S^2C^2  != empty   (#60)
```

So `stor.space<host>` is not one Communication capability:
residency changes the transfer rate by ~2-3x. It did **not**
add the legacy-default style extra HB on this SiLU arm /
named-nonblocking realization / tested N.

Do not FileCheck microseconds. Do not promote this to a
Cost axiom or a Schedule rewrite.

Records: [`v3-dataset/v3-cuda-mem.jsonl`](v3-dataset/v3-cuda-mem.jsonl).
Derived: [`v3-dataset/v3-cuda-mem-slices.csv`](v3-dataset/v3-cuda-mem-slices.csv).

---

## 4. Out of this increment

```text
managed / mapped / cudaMallocAsync
V1 p0 stream arms rewrite
D2D / P2P / Graph / multi-GPU
C_heavy || C_light
Cost v0.4 / Capability_4090 rewrite
changing S^2C^2 Semantics
claiming V3
```

---

## 5. Files

| Path | Role |
| ---- | ---- |
| `runtime/cuda/s2c2_cuda_adapter.cu` | `--cuda-val-mem=` |
| `tools/s2c2-cuda-adapter/` | host `--dry-run --cuda-val-mem` |
| `runtime/cuda/record_v3.py` | `--cuda-val-mem-sweep` / `--analyze-cuda-val-mem` |
| `docs/design/v3-dataset/v3-cuda-mem.jsonl` | 27 points |

`--cuda-val=p0` named/default bodies stay untouched.

```text
residency          !=  Cost v0.4
stor.space<host>   !=  one realization
Semantics          =  unchanged
V3                 !=  claimed
```
