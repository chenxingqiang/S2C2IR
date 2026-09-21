# scf.for loop-pipeline wall-clock (Phase 3J)

**Status:** program-level witness of the **3I `scf.for` realization**.
4090 and 910B host wall-clocks are both `measured=yes`.
Do not FileCheck microseconds. Do not compare 4090 μs to 910B μs.
Static trip in the witness. SSA `iter_args` are the double buffer.
Conservative loop-carried lifetime is inherited, not expanded.
Not Cost v0.4. Does **not** densify Capability matrices,
overwrite `#69`, invent sibling `sched.wait`, FileCheck
microseconds, or claim a generic dynamic N-tile scheduler.
Do not FileCheck 4090 μs against 910B μs.

```text
3I scf.for software pipeline
→ sequential parent-IR-order   T_seq
→ evidence-bounded KEEP C||Storage   T_evi
→ as-written concurrent   T_par
```

```text
scf.for realization
+ static trip in witness
+ SSA iter_args double buffer
+ conservative loop-carried lifetime
    ≠
arbitrary runtime-N
+ alias-complete overwrite analysis
+ general dynamic scheduler
```

```text
3I compiler structure     ≠  this wall-clock
3F two-tile witness       ≠  this loop program
logical SSD               ≠  a real disk
T_evi == T_par            ≠  a Cost axiom
#69 underdetermined       ≠  this measurement
```

## Why this cut

3I made the static N-tile realization a structured software
pipeline. That is a compiler fact. It does not answer:

```text
Does the evidence-bounded loop pipeline beat sequential
parent-IR-order on the same program, on real hardware?
```

This increment opens that program measurement. It does **not**
open Cost v0.4 and does **not** expand alias / overwrite
analysis.

## Program

Match the 3I IR (`test/Integration/storage-loop.mlir`
`@ssd_loop_pipeline`). Three tiles. Prologue materializes tile 0.
The loop body runs **trip=2**.

```text
prologue: SSD → Host → HBM tile 0
for i in {0,1}:
  seq:  compute(tile i); prefetch(i+1); HtoD(i+1)
  evi:  compute(tile i) || prefetch(i+1); then sequential HtoD(i+1)
```

Computes tiles 0 and 1. Tile 2 is only prefetched and copied
HtoD. There is no licensed `C||C` in this program, so
`T_evi == T_par` (`evi=keep-C||Storage`, `note evi-eq-par`).

```text
T_seq  = sequential parent-IR-order of the 3I program
T_evi  = evidence-bounded loop pipeline (KEEP C||Storage)
T_par  = as-written concurrent
T_baseline = T_seq
T_optimized = T_evi
ratio = T_evi / T_seq
```

`T_par` is printed for inspection. It is not the baseline.

```text
T_evi < T_seq   →  kept C||Storage overlap produced program gain
T_evi ≈ T_seq   →  report honestly; do not invent a speedup
this 4090 log   →  measured=yes; do not FileCheck μs
this 910B log   →  measured=yes; do not FileCheck μs
do not compare 4090 μs to 910B μs
```

Do not FileCheck microseconds. Do not freeze a ratio as Cost.

## Adapter stand-in

| Logical | Stand-in |
| ------- | -------- |
| SSD | pageable host `memcpy` into pinned host |
| Host | pinned host |
| HBM | device memory |
| compute | existing kernel (CUDA SiLU / Ascend elemwise) |

```text
Workload_semantic ≠ Kernel_backend
logical SSD       ≠ NVMe benchmark
```

Host protocol (`--dry-run --storage-loop-wallclock`) is the CI
witness. Timed binaries live in `runtime/{cuda,ascend}/` and
are not linked into `s2c2-opt`. `--storage-loop` remains the
3I compiler contract and must not collide with this flag.

Default measurement payload:

```text
n_tile = 4194304 floats   = 16MiB / tile
tiles  = 3
trip   = 2
k_ref  = 32
```

## Analyzer

`record_ascend.py --print-storage-loop-wallclock-contract`

`record_ascend.py --analyze-storage-loop-wallclock <log>`

Tokens only:

```text
storage-loop-wallclock program-measurement=yes
storage-loop-wallclock note scf-for-software-pipeline
storage-loop-wallclock measured=yes|no
storage-loop-wallclock t-opt-over-base-defined=yes|no
note t-base-is-t-seq
note t-opt-is-t-evi
note evi-eq-par
note not-arbitrary-runtime-n
note catalog-untouched
note logical-ssd-ne-disk
note not-cost-v04
cost=unchanged
```

A host without a device writes `measured=no`. That is a valid
result, not a guessed ratio. The protocol is covered by
`test/Pilot/storage-loop-wallclock-device-absent.log`.
Do not FileCheck microseconds.

The wall-clock logs are indexed in
[`v3-dataset/hardware-ledger.jsonl`](v3-dataset/hardware-ledger.jsonl).
`python3 runtime/record_hw_ledger.py --check-hw-ledger` re-checks
the whole set together.

## Inherited 3I compiler facts

Reuse and overlap stay exactly as 3I froze them:

```text
scf.if result          ≠ proven object identity
scf.for iter_arg       → never a proven live replica
prologue proven live   → reuse
unknown                → PRESERVE overlap; does not block reuse
```

`--s2c2-lower` still preserves `scf.for` / `scf.if`. This
increment does not add a rewrite, a capability rule, or a
new happens-before relation.

## Out of scope

```text
Cost v0.4 ranking
new 4090 / 910B Capability grid points
overwriting #69
C||Storage flatten
alias-complete overwrite / rematerialize DCE
arbitrary runtime-N scheduler
in-place stor.transfer slot overwrite
real NVMe
FileCheck of microseconds
comparing 4090 μs to 910B μs
```
