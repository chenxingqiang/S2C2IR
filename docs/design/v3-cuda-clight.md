# CUDA Validation — C_light ∥ C_heavy (compute kinds)

Status: **protocol only** (4090 not yet recorded). Not Cost
v0.4. Does **not** change Cost, HB axioms, `R`, Search,
Transformation, Pilot IR, A/B/C bodies, `--matched` /
`--phase` / `--cap` / `--pipe` bodies, V1 `--cuda-val=p0`
timed bodies, V2 `--cuda-val-mem` timed bodies, or
S^2C^2 Semantics. Baseline: `3b75d31` (`#61`).

```text
C_light || C_heavy   !=  a Cost axiom
--cuda-val-cc        !=  a new Pilot func
C || C               !=  "4090 cannot parallelize compute"
two SiLU             !=  every compute pair
V3                   !=  claimed
```

---

## 1. Why this layer

`#55` measured `C∥C` as **serial** on this SiLU arm
(two identical `k×SiLU`, same kind, same buffers class).
That is an **arm-specific** resource result, not a device
law. This increment keeps the `#60` named-nonblocking
streams that *can* overlap and asks whether a **different
compute kind** can share the device:

```text
same named nonblocking streams
+
D0 != D1
+
C_light  =  k x SiLU(vector N)
C_heavy  =  m x tiled GEMM(dim=1024)
        |
        v
does C||C stay serial, or can different kinds overlap?
```

Two different questions, kept separate:

```text
1. Same-kind control:   SiLU || SiLU     (replay #55 at this k)
2. Mixed-kind probe:    SiLU || GEMM     (matched duration, r ~ 1)
```

`#55` `C∥C = serial` would be **kind-specific** if (1)
stays serial and (2) is parallel. Both serial is also a
valid scoped result: these two kinds still contend under
this tested regime. Do not upgrade either outcome to
"4090 cannot overlap any compute" or a Cost axiom.

---

## 2. Grid

Streams stay **named nonblocking**. N in {4M, 16M, 64M}.
GEMM dimension is **1024** (the existing `--cap` tiled
stand-in; `N` is the SiLU vector length, not the matrix
dim). `k` (SiLU repeats) and `m` (GEMM repeats) are chosen
so `T_silu ~ T_matmul` (`r ~ 1`), avoiding the `#61`
r-unbalance gray zone:

```text
if T_silu_unit <= T_gemm_unit:
    k = clamp(round(T_gemm_unit / T_silu_unit), 1, 4096)
    m = 1
else:
    k = 1
    m = clamp(round(T_silu_unit / T_gemm_unit), 1, 4096)
```

`--cap` `cap-compute-compute` (two identical SiLUs) is
**not** rewritten. This is a new exclusive mode.

```text
val-cc-silu         k x SiLU(D0)
val-cc-matmul       m x GEMM(A,B,C)        dim=1024
val-cc-seq          silu then gemm, same stream
val-cc-ovl          silu || gemm, two streams, D0 != D1
val-cc-silu-silu    k x SiLU(D0) || k x SiLU(D1)
```

Correctness is gated (`correct=0` exits 3): SiLU^k spots
on the vector buffer(s); GEMM 3-index host spots on C.
Timing uses the frozen `#55` classifier. Do not FileCheck
microseconds.

`--cuda-val-cc` is mutually exclusive with `--cuda-val` /
`--cuda-val-mem` / `--matched` / `--phase` / `--cap` /
`--pipe`. V1/V2 timed bodies stay untouched.

`extra_hb = mixed-kind-serial` is a **realization
classification** from observed *serial* extra time on the
mixed-kind pair, not a reconstructed CUDA HB graph.
Same-kind serial is the `#55` control and is **not**
extra-HB.

What would count as kind-specific overlap:

```text
SiLU || SiLU   ->  serial
SiLU || GEMM   ->  parallel
```

What would count as still-serial (also in-scope):

```text
SiLU || SiLU   ->  serial
SiLU || GEMM   ->  serial     (ovl/sum >= 0.90)
```

Do not treat a `#55` mixed gray zone (`ovl/max <= 1.15`
and `ovl/sum` in (0.75, 0.90)) as extra-HB.

---

## 3. 4090 result

Pending the GPU sweep. Protocol and host FileCheck land
first. Records will be
[`v3-dataset/v3-cuda-clight.jsonl`](v3-dataset/v3-cuda-clight.jsonl)
(15 points: 3 N × 5 arms). Derived:
[`v3-dataset/v3-cuda-clight-slices.csv`](v3-dataset/v3-cuda-clight-slices.csv).

Do not FileCheck microseconds. Do not promote this to a
Cost axiom or a Schedule rewrite.

---

## 4. Out of this increment

```text
Tensor-Core-specific claims
occupancy / Nsight
cudaMallocAsync (#62, separate PR)
D2D / P2P / Graph / multi-GPU
rewriting #55 C||C cells
Cost v0.4 / Capability_4090 rewrite
changing S^2C^2 Semantics
claiming V3
```

---

## 5. Files

| Path | Role |
| ---- | ---- |
| `runtime/cuda/s2c2_cuda_adapter.cu` | `--cuda-val-cc=` |
| `tools/s2c2-cuda-adapter/` | host `--dry-run --cuda-val-cc` |
| `runtime/cuda/record_v3.py` | `--cuda-val-cc-sweep` / `--analyze-cuda-val-cc` |

`--cuda-val=p0` and `--cuda-val-mem=p0` bodies stay
untouched.

```text
C_light || C_heavy   !=  Cost v0.4
C || C               !=  one device law
Semantics            =  unchanged
V3                   !=  claimed
```
