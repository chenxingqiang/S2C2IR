# Evidence-Bounded Workload Scheduling (Phase 3E)

**Status:** compiler-driven workload realization. Not Cost v0.4.
Does **not** densify Capability matrices, overwrite `#69`, invent
`910B C||C = parallel`, add a new rewrite kind, or FileCheck
microseconds.

Phase 3D entry:
[`evidence-bounded-schedule.md`](evidence-bounded-schedule.md).

```text
s2c2-opt workload.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule
```

The IR describes **semantic concurrent** only. The compiler
discovers candidates and chooses KEEP / FLATTEN.

## Workload

One function, parent IR order:

```text
SSD  →  Host                 sequential (stor.transfer)
Host →  HBM  ||  Compute     candidate #0  C||HtoD
Compute A || Compute B       candidate #1  C||C 16MiB
Compute A || Compute B       candidate #2  C||C 128MiB
```

Same MLIR, three named profiles:

| Candidate | rtx4090 | 910B | unknown |
| --------- | ------- | ---- | ------- |
| #0 C\|\|HtoD | KEEP | KEEP | KEEP |
| #1 C\|\|C 16MiB | FLATTEN | KEEP | KEEP |
| #2 C\|\|C 128MiB | FLATTEN | FLATTEN | KEEP |

`910B` is the overlay projection, not `#69`. No evidence ⇒ KEEP.

## Candidate discovery

Every 2-task `sched.concurrent` (and `sched.overlap`) is a
candidate. The pass prints:

```text
workload-candidate #0 pair=C||HtoD ... decision=KEEP reason=relation-parallel
workload-candidate #1 pair=C||C payload=16MiB ... decision=FLATTEN reason=licensed-evidence
workload-schedule candidates=3 keep=1 flatten=2 hb=verify-with-check-s2c2-execution
```

Optional JSON dump (`dump-schedule=`), schema
`s2c2.workload_schedule.v1`. The rewrite inhabitant is still
licensed concurrent→serial. Pair kind is evidence, not a new pass.

`--check-s2c2-execution` after rewrite. `--s2c2-lower` still
produces a sequential realization.

## Runtime witness

The compiler produces the optimized IR. Runtime does **not** take
a second, hand-written optimized program.

```text
workload.mlir
    ↓  s2c2-opt --profile=… --s2c2-evidence-bounded-schedule
optimized IR + workload-candidate decisions
    ↓  --check-s2c2-execution
    ↓  --s2c2-lower
    ↓  adapter --workload-schedule   (dry-run: source=s2c2-opt)
    ↓  existing SSD+MLP wall-clock   (T_evi of this realization family)
```

Host protocol: `--dry-run --workload-schedule`.
Timed witness remains the checked-in SSD+MLP wall-clock logs
(`measured=yes`). This increment does not add grid points and
does not FileCheck microseconds.

## Out of scope

```text
Phase 3F CLI freeze / isolating logs from the compiler interface
Phase 4 extra rewrite kinds (C||HtoD flatten, pipeline, …)
Cost v0.4 ranking
new 4090 / 910B Capability measurements
overwriting #69
```
