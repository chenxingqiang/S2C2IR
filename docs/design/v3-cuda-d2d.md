# CUDA Validation — Same-Device D2D (Communication Domain)

Status: **4090 evidence recorded**. Not Cost
v0.4. Does **not** change Cost, HB axioms, `R`, Search,
Transformation, Pilot IR, A/B/C bodies, `--matched` /
`--phase` / `--cap` / `--pipe` bodies, V1 `--cuda-val=p0`,
V2 `--cuda-val-mem`, `--cuda-val-cc`, or `--cuda-val-async`
timed bodies, or S^2C^2 Semantics. Baseline: `dda0d2e`
(`#62`).

```text
D2D                    !=  a Cost axiom
--cuda-val-d2d         !=  a new Pilot func
comm.copy              !=  one CUDA memcpy kind
same-device D2D        !=  P2P
P2P                    !=  this increment
V3                     !=  claimed
```

---

## 1. Why this layer

`#60`–`#62` closed Host↔Device runtime / storage cells.
`#63` closed one compute-resource cell. The missing
Communication question is whether the **Communication
Domain** extends past Host↔Device:

```text
Host <-> Device     (#55 / #60 / #61)
        |
        v
Device <-> Device   (this increment: same GPU)
        |
        v
Device <-> Device   (later: P2P, two GPUs)
```

Three questions, kept separate:

```text
1. Rate:     T_d2d vs T_htod   (same byte count)
2. Overlap:  C || D2D vs C || HtoD   (k calibrated per copy)
3. Same-dir: D2D || D2D   (echo of #55 HtoD || HtoD)
```

P2P (`cudaDeviceCanAccessPeer`) needs two devices. This
box is treated as **one GPU** unless `device_count >= 2`.
The adapter prints `p2p_capable` / `device_count` and does
**not** enable peer access or time a P2P arm.

```text
same-device D2D     =  cudaMemcpyDeviceToDevice on one GPU
P2P                 =  a later Communication Domain cell
```

---

## 2. Grid

Named nonblocking streams. N in {4M, 16M, 64M}. Two `k`
values, both `choose_phase_k(r=1)`:

```text
k_htod  from  T_htod / T_silu(k=1)
k_d2d   from  T_d2d  / T_silu(k=1)
```

C∥D2D must not inherit the HtoD-calibrated `k`. If
`T_d2d << T_htod`, that `k` puts D2D in the `#55`
r-unbalance gray zone and both overlap and serialize look
like `T ≈ T_compute`.

```text
val-d2d-htod           1x HtoD (pinned, named stream)
val-d2d-d2d            1x D2D  dSrcA -> dDstA   (preallocated)
val-d2d-compute-htod   k_htod x SiLU
val-d2d-compute-d2d    k_d2d  x SiLU
val-d2d-ovl-htod       k_htod x SiLU || HtoD     (D0 != D1)
val-d2d-ovl-d2d        k_d2d  x SiLU || D2D      (D0 != D1)
val-d2d-d2d-d2d        D2D || D2D  two streams, distinct pairs
```

Correctness is gated (`valSpotOk`). Do not FileCheck
microseconds. `--cuda-val-d2d` is mutually exclusive
with `--cuda-val` / `--cuda-val-mem` / `--cuda-val-cc` /
`--cuda-val-async` / `--matched` / `--phase` / `--cap` /
`--pipe`.

Classifier is the frozen `#55` policy (measurement, not a
Cost axiom):

```text
par/sum >= 0.90                         -> serial
par/max <= 1.15  and  par/sum <= 0.75   -> parallel
else                                    -> mixed
```

`r < 0.3` or `r > 3.0` is the `#61` r-unbalance gray
zone. That cell does not mint `copy_engine_contention`.

Three layers stay distinct:

```text
Semantic              !=  Capability
Capability            !=  Realization constraint
No observed overlap   !=  Extra HB
Same-device D2D       !=  Extra HB
```

```text
observed_constraint    =  none | copy_engine_contention
extra_hb               =  not-applicable
```

D2D∥D2D serial on named streams is **copy-engine
contention**, not `HB_CUDA ⊃ HB_S^2C^2`. `#60` reserved
`extra_hb = legacy-default` for default-stream extra
sync.

```text
serialization/constraint
├── legacy_default          #60
├── resource_contention     #63
├── allocator_sync          #62  (not observed on 4090)
└── copy_engine_contention  this increment
```

---

## 3. Realization (not a Storage rewrite)

```text
comm.copy  HtoD   =  cudaMemcpyAsync(..., HostToDevice)
comm.copy  D2D    =  cudaMemcpyAsync(..., DeviceToDevice)
```

Same S^2C^2 `comm.copy`. Different CUDA memcpy kind.
Does **not** change `stor.materialize`. Destinations are
preallocated; this increment is Communication, not
lifetime.

Buffers for D2D∥D2D are distinct pairs. The two streams
are not secretly serialized by a wait. Overlap arms do
not insert `cudaDeviceSynchronize` between sides.

---

## 4. 4090 result (21 points -> 3 slices)

All arms `correct=1`. `device_count=1`, `p2p_capable=0`.
Protocol tree: `9521f85`. Named nonblocking. k calibrated
per copy (`r ~ 1`).

| N | k_htod | k_d2d | htod | d2d | htod/d2d | C\|\|HtoD | C\|\|D2D | D2D\|\|D2D | observed_constraint | extra_hb |
| - | ------ | ----- | ---- | --- | -------- | --------- | -------- | ---------- | ------------------- | -------- |
| 4M | 32 | 1 | 670 | 18 | 37.4 | parallel | mixed | serial | copy_engine_contention | not-applicable |
| 16M | 49 | 2 | 2659 | 108 | 24.6 | parallel | serial | serial | copy_engine_contention | not-applicable |
| 64M | 20 | 1 | 10611 | 547 | 19.4 | parallel | serial | serial | copy_engine_contention | not-applicable |

```text
T_htod / T_d2d          =  37.4 / 24.6 / 19.4
C || HtoD               =  parallel / parallel / parallel
D2D || D2D              =  serial   / serial   / serial
C || D2D                =  mixed    / serial   / serial
r_d2d                   =  1.04 / 1.10 / 1.00   (not gray-zone)
copy_engine_contention  =  3
p2p                     =  out-of-increment
extra_hb                =  not-applicable
```

Same-device D2D is a **faster** `comm.copy` realization
than pinned HtoD on this box. That is a Communication
**rate** fact, not a Cost axiom.

`D2D || D2D` is serial on named streams: same-direction
device copies do not overlap. That is
`copy_engine_contention`, echoing `#55` `HtoD || HtoD`,
not extra HB.

`C || HtoD` stays parallel (control, matches `#55` /
`#56` / `#60` named). `C || D2D` does **not** match that
control at 16M/64M: with balanced `k_d2d` the pair is
sum-like. Both sides are device-memory traffic. Do not
call that extra HB, P2P, or "4090 cannot overlap
compute". Do not mint a Cost D2D penalty from three
points.

```text
comm.copy Host<->Device     can hide behind C   (this regime)
comm.copy Device<->Device   same GPU, this arm  does not
Legal SW                    !=  Extra HB
copy_engine_contention      !=  extra_hb
P2P                         !=  claimed
```

Records: [`v3-dataset/v3-cuda-d2d.jsonl`](v3-dataset/v3-cuda-d2d.jsonl).
Derived: [`v3-dataset/v3-cuda-d2d-slices.csv`](v3-dataset/v3-cuda-d2d-slices.csv).

---

## 5. Out of this increment

```text
V1 / V2 / cc / async timed-body rewrite
P2P / cudaDeviceEnablePeerAccess / multi-GPU
NVLink / GPUDirect
allocator pool pressure
CUDA Graph / stream-count
Cost v0.4
changing S^2C^2 Semantics
claiming V3
```

---

## 6. Files

| Path | Role |
| ---- | ---- |
| `runtime/cuda/s2c2_cuda_adapter.cu` | `--cuda-val-d2d=` |
| `tools/s2c2-cuda-adapter/` | host `--dry-run --cuda-val-d2d` |
| `runtime/cuda/record_v3.py` | `--cuda-val-d2d-sweep` / `--analyze-cuda-val-d2d` |
| `docs/design/v3-dataset/v3-cuda-d2d.jsonl` | 21 points |

```text
same-device D2D         !=  P2P
copy_engine_contention  !=  extra HB
comm.copy               !=  one CUDA memcpy kind
Semantics               =  unchanged
V3                      !=  claimed
```
