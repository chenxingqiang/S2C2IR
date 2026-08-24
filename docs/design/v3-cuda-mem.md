# CUDA Validation — Pinned vs Pageable (V2 P0)

Status: **protocol only**. 4090 not yet recorded. Not Cost
v0.4. Does **not** change Cost, HB axioms, `R`, Search,
Transformation, Pilot IR, A/B/C bodies, `--matched` /
`--phase` / `--cap` / `--pipe` bodies, V1 `--cuda-val=p0`
timed bodies, or S^2C^2 Semantics. Baseline: `e44d577`
(`#60`).

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

That would be a second realization counterexample:

```text
stor.space<host>  cannot mean "any host buffer"
host residency    may decide comm realization capability
```

Not a bandwidth paper. The question is

```text
Storage Capability
    <->  Communication Capability
    <->  Overlap
```

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
classification** from observed serialization, not a
reconstructed CUDA HB graph. Phrase as:

> observed extra serialization consistent with pageable-host
> staging / implicit synchronization

What would count as the Storage x Comm counterexample:

```text
pinned   C||HtoD  ->  parallel     (confirms #60 named)
pageable C||HtoD  ->  serial|mixed
```

and/or the same flip on C||DtoH. A bandwidth-only gap
(`T_pageable > T_pinned`) **without** a verdict flip is
reported, but is not by itself the Storage x Comm claim.

---

## 3. Out of this increment

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

## 4. Files

| Path | Role |
| ---- | ---- |
| `runtime/cuda/s2c2_cuda_adapter.cu` | `--cuda-val-mem=` |
| `tools/s2c2-cuda-adapter/` | host `--dry-run --cuda-val-mem` |
| `runtime/cuda/record_v3.py` | `--cuda-val-mem-sweep` / `--analyze-cuda-val-mem` |
| `docs/design/v3-dataset/v3-cuda-mem.jsonl` | after 4090 (27 points) |

`--cuda-val=p0` named/default bodies stay untouched.

```text
residency          !=  Cost v0.4
stor.space<host>   !=  one realization
Semantics          =  unchanged
V3                 !=  claimed
```
