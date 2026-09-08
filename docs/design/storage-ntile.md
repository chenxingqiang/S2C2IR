# N-tile Contract + Three-Tile Realization (Phase 3H)

**Status:** N-tile pipeline **contract** with an **N=3 unrolled**
realization. Not an arbitrary-N / `scf.for` software pipeline.
KEEP_RESIDENCY reuses a live replica only when proven safe. Not
Cost v0.4. Does **not** flatten `C||Storage`, invent sibling
`sched.wait`, densify Capability matrices, or overwrite `#69`.
This increment is compiler / integration semantics. The checked-in
`storage-pipeline-4090.log` is the inherited 3F program witness,
not a new three-tile wall-clock.

Phase 3G entry:
[`storage-hierarchy.md`](storage-hierarchy.md).

```text
SSD → Host
        ↘
        Compute(tile i)
        ↘
     HtoD(tile i+1)
        ↘
     Compute(tile i+1) || prefetch(tile i+2)
```

3G reported the hierarchy plan. 3H realizes two things:

1. The N-tile pipeline contract, realized as **three unrolled tiles**.
2. Proven-safe reuse of an already-valid residency.

## Proven-safe reuse

`KEEP_RESIDENCY` still prints for every rematerialize temptation.
Reuse **applies** only when all of these hold:

```text
same object identity
same dest type / space
live replica dominates in the same block
no intervening stor.pack / stor.dealloc of that replica
site is sequential (not inside sched.concurrent)
```

Otherwise the rematerialize stays (`skipped`). This is not a generic
data-movement DCE and not `C||Storage` flatten.

```text
inferred overlap  →  PREFETCH (KEEP only)
unknown           →  PRESERVE the overlap site
proven live replica → reuse (profile-independent lifetime)
unproven rematerialize → skip
```

No invented sibling `sched.wait`.

## Workload

`test/Integration/storage-ntile.mlir` (`@ssd_ntile_pipeline`):

```text
SSD→Host→HBM tile 0            MATERIALIZE + TRANSFER
Compute 0 || prefetch 1        PREFETCH if overlap evidence
HtoD tile 1                    TRANSFER (consume live host)
Compute 1 || prefetch 2        PREFETCH if overlap evidence
HtoD tile 2 + compute 2        TRANSFER then sequential compute
rematerialize tile 1           KEEP_RESIDENCY → reuse if proven
```

| Site | rtx4090 | 910B | unknown |
| ---- | ------- | ---- | ------- |
| C\|\|Storage prefetch ×2 | PREFETCH | PREFETCH | PRESERVE |
| sequential HtoD | TRANSFER | TRANSFER | TRANSFER |
| rematerialize temptation | reuse | reuse | reuse |

Runtime witness remains the inherited 3F log
`storage-pipeline-4090.log` (`measured=yes`). It is **not** a new
three-tile wall-clock. Logical SSD is a pageable host buffer, not
NVMe. Do not FileCheck microseconds.

## Out of scope

```text
generic rematerialize elimination / alias-incomplete DCE
C||Storage flatten
arbitrary-N / scf.for double-buffer software pipeline
Phase 4 Cost v0.4
new 4090 / 910B Capability measurements
overwriting #69
```
