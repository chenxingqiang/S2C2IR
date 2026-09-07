# Storage-Aware Pipeline Scheduling (Phase 3F)

**Status:** two-tile SSD prefetch || compute. Not Cost v0.4.
Does **not** densify Capability matrices, overwrite `#69`, invent
`910B C||C = parallel`, add a new rewrite kind, FileCheck
microseconds, or become a generic heterogeneous scheduler.

Phase 3E entry:
[`evidence-bounded-workload.md`](evidence-bounded-workload.md).

```text
Storage → Data Movement → Compute Overlap → Schedule Realization
```

The compiler optimizes the **lifetime of data from SSD to the
compute unit**, not a GPU kernel in isolation.

```text
SSD
 ↓
Prefetch
 ↓
HtoD
 ↓
Gated MLP / Compute Tile
 ↓
Prefetch next tile
```

## Workload

One function, parent IR order. Semantic concurrent only:

```text
SSD → Host → HBM                 tile 0 prologue (sequential)
Compute tile 0 || SSD prefetch   candidate #0  C||Storage
Host → HBM                       tile 1 HtoD (sequential)
Compute A || Compute B           candidate #1  C||C 16MiB
Compute A || Compute B           candidate #2  C||C 128MiB
```

```text
SSD prefetch || Compute
        ↓
      HtoD
        ↓
Compute_A || Compute_B
```

Same MLIR, three named profiles:

| Candidate | rtx4090 | 910B | unknown |
| --------- | ------- | ---- | ------- |
| #0 C\|\|Storage | KEEP | KEEP | PRESERVE |
| #1 C\|\|C 16MiB | FLATTEN | PRESERVE | PRESERVE |
| #2 C\|\|C 128MiB | FLATTEN | FLATTEN | PRESERVE |

```text
Storage/Communication can overlap     → KEEP
Compute/Compute licensed contention   → FLATTEN
No evidence                           → PRESERVE
```

`C||Storage` is SSD↔Host movement beside compute. It is **inferred**
overlap (same class as `C||HtoD`), not a new 4090/910B grid point
and not `#69`. `910B` C||C bands remain the overlay projection.

The rewrite inhabitant is still licensed concurrent→serial.
No double-buffering rewrite, no pipeline op lowering, no new
`sched.serial`.

## Why this stays on Storage

```text
SSD → materialize → residency → transfer → event → compute → pipeline
```

S²C²'s identity is Storage + Communication + Compute + HB in one
execution IR. This increment realizes:

```text
storage locality + data-movement overlap + compute scheduling
```

It does **not** open kernel fusion, generic tile search, or
Cost-based heterogeneous scheduling.

## Runtime witness

Same protocol as Phase 3E: `s2c2-opt` produces the optimized IR.
Adapters `--dry-run --workload-schedule` (`source=s2c2-opt`).
Timed witness remains the checked-in SSD+MLP wall-clock logs.
No new hardware, no new grid points, no FileCheck of microseconds.

## Out of scope

```text
Phase 3G storage hierarchy (SSD ↔ DRAM ↔ HBM ↔ Compute)
  — when to materialize / prefetch / transfer / keep residency
Phase 4 Cost-based heterogeneous scheduling / Cost v0.4
full double-buffering loop / N-tile software pipeline
new rewrite kinds (pipeline realization, C||Storage flatten)
new 4090 / 910B Capability measurements
overwriting #69
```
