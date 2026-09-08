# scf.for Storage Pipeline (Phase 3I)

**Status:** `scf.for` software-pipeline **realization** with a static
trip count in the test workload, SSA iter_args as the double buffer,
and loop-carried KEEP_RESIDENCY safety. Not an in-place
`stor.transfer` overwrite. Not Cost v0.4. Does **not** flatten
`C||Storage`, invent sibling `sched.wait`, densify Capability
matrices, or overwrite `#69`. This increment is compiler /
integration semantics. The checked-in `storage-pipeline-4090.log`
is the inherited 3F two-tile witness. The 3I loop program
wall-clock is Phase 3J
([`storage-loop-wallclock.md`](storage-loop-wallclock.md)).

Phase 3H entry:
[`storage-ntile.md`](storage-ntile.md).

```text
prologue tile 0: SSD → Host → HBM → Compute0
for i:
    compute(i) || prefetch(i+1)
    HtoD(i+1)
    consume(i+1)
```

3H unrolled three tiles. 3I turns that static expansion into a
structured loop. The test trip is **N=2 iterations after a
prologue tile** (three tiles total). Next-SSD selection uses
`scf.if` on `i+1` (same underdetermined identity as an
`scf.index_switch` of the next tile). Object identity through that
select is **underdetermined**.

```text
✅ scf.for storage-pipeline realization
✅ SSA iter_args as double-buffer
✅ loop-invariant prologue reuse
❌ arbitrary runtime-N / alias-complete dynamic scheduler
❌ in-place stor.transfer slot overwrite
❌ new hardware wall-clock (see 3J)
```

## Loop-carried reuse

`KEEP_RESIDENCY` still prints for every rematerialize temptation.
Reuse **applies** only when all of these hold:

```text
same object identity
same dest type / space
site is sequential (not inside sched.concurrent)
and either:
  live replica dominates in the same block
  + no intervening pack/dealloc (including nested scf.for)
or:
  live replica is defined before the enclosing scf.for
  + the loop does not pack/dealloc that replica
```

Otherwise the rematerialize stays (`skipped`). A `scf.for`
iter_arg is **never** treated as a proven live replica
(`loop-carried-underdetermined`). `scf.if` / `scf.index_switch` results do
not establish object identity.

```text
inferred overlap  →  PREFETCH (KEEP only)
unknown           →  PRESERVE the overlap site
proven live replica → reuse (profile-independent lifetime)
unproven rematerialize → skip
```

No invented sibling `sched.wait`. The loop is reported, not
rewritten.

## Workload

`test/Integration/storage-loop.mlir` (`@ssd_loop_pipeline`):

```text
SSD→Host→HBM tile 0            MATERIALIZE + TRANSFER
scf.for i=0..2 (trip=2)
  Compute(i) || prefetch(i+1)  PREFETCH if overlap evidence
  HtoD tile i+1                TRANSFER
  rematerialize tile 0 host    KEEP_RESIDENCY → reuse if proven
after loop: rematerialize t0   KEEP_RESIDENCY → reuse
after loop: rematerialize t1   MATERIALIZE (switch identity unknown)
```

| Site | rtx4090 | 910B | unknown |
| ---- | ------- | ---- | ------- |
| C\|\|Storage prefetch ×1 (in loop) | PREFETCH | PREFETCH | PRESERVE |
| sequential HtoD | TRANSFER | TRANSFER | TRANSFER |
| prologue rematerialize | reuse | reuse | reuse |

Runtime witness of the **loop program** is Phase 3J
([`storage-loop-wallclock.md`](storage-loop-wallclock.md)).
The inherited 3F log `storage-pipeline-4090.log` remains the
two-tile witness. Logical SSD is a pageable host buffer, not NVMe.
Do not FileCheck microseconds. `--s2c2-lower` keeps `scf.for` /
`scf.if` and converts `!stor.buffer` carried through `scf.if` to
memref. It does not invent `sched.wait`.

## Out of scope

```text
generic rematerialize elimination / alias-incomplete DCE
C||Storage flatten
in-place double-buffer slot overwrite
fully dynamic-N alias / overwrite scheduler
Phase 4 Cost v0.4
new 4090 / 910B Capability measurements
overwriting #69
```
