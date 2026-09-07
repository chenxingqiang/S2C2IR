# Complete SSD + MLP program wall-clock

**Status:** protocol + compiler witness. Device timing is
`measured=no` until a 4090 / 910B run writes a log. Not Cost
v0.4. Does **not** densify Capability matrices, overwrite
`#69`, invent `910B C||C = parallel`, FileCheck microseconds,
or claim full-model inference.

```text
Same complete SSD+MLP program
→ evidence-bounded schedule
→ host wall-clock T_evi / T_seq
```

```text
Stage A/B C||C          ≠  this program measurement
--s2c2-lower            ≠  T_baseline
logical SSD             ≠  a real disk
comp.gated_mlp          ≠  the adapter kernel
seq-slack=1.05          ≠  a Cost axiom
#69 underdetermined     ≠  this overlay
```

## Why this cut

`#75` showed scoped evidence can change a legal realization.
`#76` wired that into a minimum E2E compiler slice, and reused
the licensed `C||C` A/B as `T_opt/T_base`. That A/B is a
**stage measurement**. It does not answer:

```text
After the compiler is allowed to change the schedule,
does the chosen realization beat naive sequential
execution on the complete SSD-streaming Gated MLP program?
```

This increment opens that program measurement.

## Program

One S²C² function, two stages, parent IR order between them:

```text
1. SSD prefetch || Gated MLP     C||HtoD
   next-layer down-proj stream ∥ current gated MLP
   independent objects; no invented sibling wait

2. C||C at 128MiB                licensed serial band
   two elemwise siblings
```

IR sizes:

| Stage | Payload | Pair |
| ----- | ------- | ---- |
| prefetch | `11008×4096×f16` ≈ 86MiB | `C\|\|HtoD` (16MiB..256MiB) |
| MLP | Llama-7B FFN (`1×4096`, `4096×11008`, `11008×4096`) | compute side of stage 1 |
| C\|\|C | `N=32M` f32 = 128MiB | overlay serial + A/B license |

Same IR, three catalogs:

| Stage | 4090 | 910B overlay | `#69` catalog |
| ----- | ---- | ------------ | ------------- |
| prefetch \|\| MLP | keep (`C\|\|HtoD` parallel) | keep (no overlay cell) | keep (`underdetermined`) |
| C\|\|C 128MiB | serialize | serialize (licensed) | keep (`underdetermined`) |

`--check-s2c2-execution` after rewrite. Flattening is parent
IR order. No sibling `sched.wait`.

## Arms

```text
T_seq  = sequential parent-IR-order of the whole program
         HtoD; then MLP; then C1; then C2
T_evi  = evidence-bounded schedule
         keep C||HtoD concurrent; flatten licensed C||C
T_par  = as-written concurrent
         keep both stages concurrent
```

```text
T_baseline  = T_seq
T_optimized = T_evi
ratio       = T_evi / T_seq
```

`T_par` is printed for inspection. It is not the baseline.
`#76` stage A/B (`T_seq/T_par` on `C||C` alone) stays a
stage measurement and is not this ratio.

```text
T_evi < T_seq   →  kept C||HtoD overlap produced program gain
T_evi ≈ T_seq   →  report honestly; do not invent a speedup
device absent   →  measured=no; ratio undefined
```

Do not FileCheck microseconds. Do not freeze a ratio as Cost.

## Adapter stand-in

| Logical | Stand-in |
| ------- | -------- |
| SSD | pinned host (`cudaHostAlloc` / `aclrtMallocHost`) |
| HBM | device memory |
| `comm.stream` | async HtoD |
| `comp.gated_mlp` | existing compute kernel (CUDA SiLU/GEMM or Ascend elemwise) |
| licensed `C\|\|C` | two compute siblings, then sequential flatten |

```text
Workload_semantic ≠ Kernel_backend
logical SSD       ≠ NVMe benchmark
```

Host protocol (`--dry-run --ssd-mlp-wallclock`) is the CI
witness. Timed binaries live in `runtime/{cuda,ascend}/` and
are not linked into `s2c2-opt`.

Default measurement payload (adapter `N`, not IR shape):

```text
n_htod = 22528000 floats   ≈ 86MiB  (down-proj xf16 bytes)
n_cc   = 33554432 floats   = 128MiB (licensed C||C band)
k_ref  = 32
```

## Analyzer

`record_ascend.py --print-ssd-mlp-wallclock-contract`

`record_ascend.py --analyze-ssd-mlp-wallclock <log>`

Tokens only:

```text
ssd-mlp-wallclock program-measurement=yes
ssd-mlp-wallclock note not-stage-ab
ssd-mlp-wallclock measured=yes|no
ssd-mlp-wallclock t-opt-over-base-defined=yes|no
ssd-mlp-wallclock note t-base-is-t-seq
ssd-mlp-wallclock note t-opt-is-t-evi
ssd-mlp-wallclock note catalog-untouched
ssd-mlp-wallclock note logical-ssd-ne-disk
ssd-mlp-wallclock note 32M-outlier-not-cost
ssd-mlp-wallclock cost=unchanged
```

A host without a device writes `measured=no`. That is a valid
result, not a guessed ratio.

The wall-clock log is indexed with the other hardware artifacts
in [`v3-dataset/hardware-ledger.jsonl`](v3-dataset/hardware-ledger.jsonl).
A later on-device run overwrites this same path, then
`python3 runtime/record_hw_ledger.py --check-hw-ledger` re-checks
the whole set together.

## Out of scope

```text
Cost v0.4 ranking
new 4090 / 910B Capability grid points
overwriting #69
real NVMe / full Llama decode
D2D / P2P / ROCm
FileCheck of microseconds
```
