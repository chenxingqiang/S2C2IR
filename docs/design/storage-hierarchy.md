# Storage Hierarchy Scheduling (Phase 3G)

**Status:** compiler decides materialize / prefetch / residency / overlap.
Not Cost v0.4. Does **not** densify Capability matrices, overwrite `#69`,
invent `910B C||C = parallel`, flatten `C||Storage`, FileCheck
microseconds, or become a generic heterogeneous scheduler.

Phase 3F entry:
[`storage-aware-pipeline.md`](storage-aware-pipeline.md).

```text
SSD ↔ Host/DRAM ↔ HBM ↔ Compute
```

3F established that SSD prefetch || compute is a KEEP overlap.
3G asks the next storage questions:

```text
when to materialize
when to prefetch
which residencies to keep
which movements are worth overlapping
```

The compiler answers from the semantic IR plus the same evidence
catalog. It does **not** rank by Cost.

## Decisions

```text
MATERIALIZE      first SSD / first host residency (eager prologue)
PREFETCH         SSD↔Host (or C||HtoD) beside independent compute
TRANSFER         Host→HBM required to consume
KEEP_RESIDENCY   later transfer would rematerialize a live space
PRESERVE         no overlap evidence — leave the site as written
```

```text
inferred overlap  →  PREFETCH (KEEP only)
inferred overlap  ↛  FLATTEN / serialize / rematerialize rewrite
unknown           →  PRESERVE the overlap site
live SSA residency → KEEP_RESIDENCY (report; reuse only if proven)
```

`KEEP_RESIDENCY` means the schedule's intended copy is the already
valid host or HBM replica. Phase 3H reuses that replica only when
dominance, type, object identity, and no intervening pack/dealloc
are proven. It does **not** flatten `C||Storage` and does **not**
invent sibling `sched.wait`. N-tile realization:
[`storage-ntile.md`](storage-ntile.md).

## Workload

`test/Integration/storage-hierarchy.mlir` (`@ssd_hierarchy_lifetime`):

```text
SSD materialize tile0 / tile1     MATERIALIZE (eager)
SSD → Host → HBM   tile 0         MATERIALIZE + TRANSFER
Compute || SSD→Host tile 1        PREFETCH if overlap evidence
Host → HBM         tile 1         TRANSFER (consume live host)
SSD → Host         tile 1 again   KEEP_RESIDENCY
Host → HBM         tile 1 again   KEEP_RESIDENCY
```

Same MLIR, three named profiles:

| Site | rtx4090 | 910B | unknown |
| ---- | ------- | ---- | ------- |
| first host tile0 | MATERIALIZE | MATERIALIZE | MATERIALIZE |
| C\|\|Storage prefetch | PREFETCH | PREFETCH | PRESERVE |
| sequential HtoD | TRANSFER | TRANSFER | TRANSFER |
| rematerialize temptation | KEEP_RESIDENCY | KEEP_RESIDENCY | KEEP_RESIDENCY |

Rewrite inhabitant is still licensed concurrent→serial. 3G adds
no flatten of `C||Storage` and no rematerialize elision.

## Runtime witness

Host protocol:

```text
s2c2-cuda-adapter --dry-run --storage-hierarchy
s2c2-ascend-adapter --dry-run --storage-hierarchy
```

Timed witness remains `storage-pipeline-4090.log` (`measured=yes`).
Logical SSD is a pageable host buffer, not NVMe. Do not FileCheck
microseconds. Do not freeze `T_evi/T_seq` as Cost. `#69` untouched.

## Out of scope

```text
Phase 3H N-tile contract + N=3 unrolled realization
  ([storage-ntile.md](storage-ntile.md))
generic rematerialize elimination
C||Storage flatten
full software-pipelined loop (scf.for)
Phase 4 Cost-based heterogeneous scheduling / Cost v0.4
new 4090 / 910B Capability measurements
overwriting #69
```
