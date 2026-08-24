# CUDA Validation — Async Alloc + Cross-Stream Wait (V2 P1)

Status: **4090 evidence recorded**. Not Cost
v0.4. Does **not** change Cost, HB axioms, `R`, Search,
Transformation, Pilot IR, A/B/C bodies, `--matched` /
`--phase` / `--cap` / `--pipe` bodies, V1 `--cuda-val=p0`
or V2 `--cuda-val-mem` timed bodies, `--cuda-val-cc` timed
bodies, or S^2C^2 Semantics. Baseline: `ab9029c` (`#63`).

```text
cudaMallocAsync        !=  a Cost axiom
--cuda-val-async       !=  a new Pilot func
stor.materialize       !=  one CUDA allocator
cross-stream wait      !=  a Schedule rewrite
V3                     !=  claimed
```

---

## 1. Why this layer

`#60` showed runtime stream realization can add extra HB.
`#61` showed host residency changes Communication rate
without adding extra HB on named streams.

This increment connects **Storage lifetime** to the already
frozen Event / HB chain:

```text
stor.materialize
    -> write
    -> event
    -> cross-stream wait
    -> read
    -> release
```

Two questions, kept separate:

```text
1. Does sync cudaMalloc/cudaFree add extra latency / HB
   versus cudaMallocAsync/cudaFreeAsync?
2. Does an explicit StreamWaitEvent realize the legal
   HB edge without a leftover serial flip?
```

A missing wait before a cross-stream read is a data race
and is **not** timed.

---

## 2. Grid

Named nonblocking streams. N in {4M, 16M, 64M}. `k` from
`T_copy` and `T_compute(k=1)`, same `r ~ 1` policy. All
lifetime arms share that `k`.

```text
val-async-copy         1x HtoD on a preallocated dest
val-async-compute      kx SiLU on a preallocated dest
val-async-life-sync    cudaMalloc + HtoD + kx SiLU + DtoH-check + cudaFree
val-async-life-async   MallocAsync + HtoD + kx SiLU + DtoH-check + FreeAsync
val-async-hb           MallocAsync(sA) + HtoD(sA) + EventRecord
                       + StreamWaitEvent(sB) + kx SiLU(sB)
                       + wait-back + DtoH-check + FreeAsync(sA)
```

Correctness is gated (`SiLU^k`). Do not FileCheck
microseconds. `--cuda-val-async` is mutually exclusive
with `--cuda-val` / `--cuda-val-mem` / `--cuda-val-cc` /
`--matched` / `--phase` / `--cap` / `--pipe`.

Three layers stay distinct (`#63`):

```text
Semantic              !=  Capability
Capability            !=  Realization constraint
No extra latency      !=  Extra HB
Legal wait            !=  Extra HB
```

```text
observed_constraint    =  none | allocator_sync
extra_hb               =  not-applicable
```

`T_life_sync / T_life_async >= 1.15` is an allocator
**rate** gap (`observed_constraint = allocator_sync`), not
`HB_CUDA ⊃ HB_S^2C^2`. `#60` reserved `extra_hb =
legacy-default` for default-stream extra sync. The
explicit wait arm is legal S^2C^2 HB.

---

## 3. 4090 result (15 points -> 3 slices)

All arms `correct=1`. Protocol tree: `fd5088f`.

| N | k | r | copy | compute | life_sync | life_async | hb | sync/async | hb/async | observed_constraint | extra_hb |
| - | - | - | ---- | ------- | --------- | ---------- | -- | ---------- | -------- | ------------------- | -------- |
| 4M | 35 | 0.594 | 670 | 398 | 1904 | 1925 | 1932 | 0.989 | 1.004 | none | not-applicable |
| 16M | 42 | 1.102 | 2659 | 2930 | 8492 | 9186 | 9182 | 0.924 | 1.000 | none | not-applicable |
| 64M | 20 | 1.093 | 10611 | 11597 | 33440 | 38400 | 38403 | 0.871 | 1.000 | none | not-applicable |

```text
T_hb / T_life_async     =  1.004 / 1.000 / 1.000
T_life_sync / T_async   =  0.989 / 0.924 / 0.871
allocator_sync          =  0
extra_hb                =  not-applicable
```

The explicit wait chain matches same-stream async
lifetime: that is **legal HB**, not extra HB. Sync
`cudaMalloc`/`cudaFree` did **not** add an allocator-sync
rate gap on this arm; the async pool path was equal or
slower. Do not upgrade that to "async alloc is always
faster", to extra HB, or to a Cost axiom.

```text
stor.materialize -> write -> event -> wait -> read -> release
    is a correct, timed CUDA realization of legal HB
observed_constraint     =  none            (this regime)
extra_hb                =  not-applicable
Semantics               =  unchanged
```

Records: [`v3-dataset/v3-cuda-async.jsonl`](v3-dataset/v3-cuda-async.jsonl).
Derived: [`v3-dataset/v3-cuda-async-slices.csv`](v3-dataset/v3-cuda-async-slices.csv).

---

## 4. Out of this increment

```text
V1 / V2 timed-body rewrite
managed / mapped / graph / multi-GPU
C_heavy || C_light   (#63, merged)
Cost v0.4
changing S^2C^2 Semantics
claiming V3
```

---

## 5. Files

| Path | Role |
| ---- | ---- |
| `runtime/cuda/s2c2_cuda_adapter.cu` | `--cuda-val-async=` |
| `tools/s2c2-cuda-adapter/` | host `--dry-run --cuda-val-async` |
| `runtime/cuda/record_v3.py` | `--cuda-val-async-sweep` / `--analyze-cuda-val-async` |
| `docs/design/v3-dataset/v3-cuda-async.jsonl` | 15 points |

```text
allocation realization  !=  Cost v0.4
explicit wait           =  legal HB  !=  extra HB
allocator_sync          !=  extra HB
Semantics               =  unchanged
V3                      !=  claimed
```
