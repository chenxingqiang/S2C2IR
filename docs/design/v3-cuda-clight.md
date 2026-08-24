# CUDA Validation — C_light ∥ C_heavy (compute kinds)

Status: **4090 evidence recorded**. Not Cost
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
No observed overlap  !=  Extra HB
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
2. Mixed-kind probe:    SiLU || GEMM     (duration approximately
                                          balanced / outside the
                                          #61 unbalance gray zone)
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
so `T_silu` and `T_matmul` are approximately balanced
(outside the `#61` r-unbalance gray zone). `r = 1` is the
target, not a lock:

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

Three layers stay distinct:

```text
Semantic              !=  Capability
Capability            !=  Realization constraint
No observed overlap   !=  Extra HB
```

The mixed-kind probe reports:

```text
pair_relation          =  serial | parallel | mixed
observed_constraint    =  none | resource_contention
extra_hb               =  not-applicable
```

`T_ovl ≈ T_seq` on **named nonblocking** streams is
Capability serial from resource contention (SM / occupancy
/ scheduler), not `HB_CUDA ⊃ HB_S^2C^2`. `#60` reserved
`extra_hb = legacy-default` for the default-stream
realization that *does* add extra HB. This increment does
not reuse that ontology.

Same-kind serial is the `#55` control. It is a pair
relation, not extra-HB.

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
and `ovl/sum` in (0.75, 0.90)) as resource contention.

---

## 3. 4090 result (15 points -> 3 slices)

All arms `correct=1`. Named nonblocking streams. GEMM
`dim=1024`. `k`/`m` calibrated to be approximately
balanced / gray-zone-excluded (4M: k=16 m=1 r=0.547;
16M: k=3 m=1 r=0.751; 64M: k=1 m=2 r=0.785). Same-kind
SiLU||SiLU stays serial/mixed (confirms `#55` on this arm;
16M is again degraded). Mixed-kind SiLU||GEMM is
**serial** at all 3 N: `T_ovl ≈ T_seq`, `ovl/sum ≥ 0.90`,
`ovl/max > 1.15`. That is not the `#61` r-unbalance gray
zone.

| N | k | m | r | silu | gemm | seq | ovl | silu||silu | ovl/max | ovl/sum | pair_relation | same | observed_constraint |
| - | - | - | - | ---- | ---- | --- | --- | ---------- | ------- | ------- | ------------- | ---- | ------------------- |
| 4M | 16 | 1 | 0.547 | 189 | 346 | 522 | 506 | 332 | 1.465 | 0.947 | serial | mixed | resource_contention |
| 16M | 3 | 1 | 0.751 | 263 | 350 | 580 | 630 | 824 | 1.799 | 1.027 | serial | serial | resource_contention |
| 64M | 1 | 2 | 0.785 | 539 | 686 | 1212 | 1212 | 1119 | 1.766 | 0.989 | serial | serial | resource_contention |

```text
kind-specific overlap     :  0
still-serial              :  2     (16M + 64M)
resource_contention       :  3
unexpected-same-kind      :  0
extra_hb                  :  not-applicable
```

4M same-kind is `#55` mixed (`ss/max=1.758`, `ss/sum=0.879`):
not parallel, not extra-HB.
16M same-kind is degraded serial (`ss/sum=1.565`), same
shape as `#55` C||C at 16M.

```text
SiLU || SiLU     serial/mixed   (this arm, this k)
SiLU || GEMM     serial         (T_ovl ~ T_seq)
pair_relation    serial         under this tested regime
observed_constraint = resource_contention
extra_hb            = not-applicable
```

Approved scoped claim, if this increment is accepted:

```text
Capability(C_SiLU, C_GEMM)  =  serial
    under the tested 4090 regime
```

Not:

```text
HB_CUDA  ⊃  HB_S^2C^2
```

`#60` vs this increment:

```text
#60  C||HtoD  default stream :  pair_relation=serial
                                observed_constraint=legacy_default
                                extra_hb=legacy-default

#63  SiLU||GEMM  named      :  pair_relation=serial
                                observed_constraint=resource_contention
                                extra_hb=not-applicable
```

Same pair_relation, different compiler problem.
Do not upgrade resource contention to "4090 cannot overlap
any compute": this GEMM is a small tiled stand-in
(~12 MB), not a Tensor-Core occupancy study.

Records: [`v3-dataset/v3-cuda-clight.jsonl`](v3-dataset/v3-cuda-clight.jsonl)
(15/15 probe points unchanged). Derived:
[`v3-dataset/v3-cuda-clight-slices.csv`](v3-dataset/v3-cuda-clight-slices.csv).

Do not FileCheck microseconds. Do not promote this to a
Cost axiom or a Schedule rewrite.

---

## 4. Out of this increment

```text
Tensor-Core-specific claims
occupancy / Nsight
cudaMallocAsync (#62, merged)
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
| `docs/design/v3-dataset/v3-cuda-clight.jsonl` | 15 points |

`--cuda-val=p0` and `--cuda-val-mem=p0` bodies stay
untouched.

```text
C_light || C_heavy   !=  Cost v0.4
C || C               !=  one device law
No observed overlap  !=  Extra HB
Semantics            =  unchanged
V3                   !=  claimed
```
