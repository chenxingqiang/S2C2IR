# Measured Storage Campaign Freeze (Phases 5A–5D)

**Status:** FROZEN. Phases 5A, 5B, 5C, and 5D are closed
evidence. Design of each cut was approved in order
(`#95`/`#96`, `#97`/`#98`, `#99`/`#100`, `#101`/`#102`).
Both 4090 and 910B measured every legal inhabitant of every
existing fully enumerated \(|F|>2\) on current Storage IR.
ArgMin was `default-3g` every time (`diverge=no`).
That is a complete positive result. Do **not** hunt for
`diverge=yes` by retuning workload. Phase **5E is not
opened**: there is no `S_measured ≠ S_default-3g` to rewrite.

```text
Goal     freeze the completed measured-ranking campaign
Not      a new enumerator, a fifth schedule, or 5E
Not      another pass over frozen 5A/5B/5C/5D sets
Rewrite  only after a later real diverge=yes on a new F
```

```text
Legality              ≠  Selection  ≠  Cost
cost-v04              ≠  measured-storage-v1     (frozen)
measured-storage-v1   ≠  default-3g
diverge=no            ≠  the two policies are the same object
ranking               ≠  rewrite license
5A ≠ 5B ≠ 5C ≠ 5D     ≠  the same F re-measured
```

## What was measured

| Phase | Workload | \|F\| | Axes | 4090 | 910B |
| ----- | -------- | ----- | ---- | ---- | ---- |
| 5A | `@ssd_pipeline_two_tiles` | 2 | one PREFETCH/PRESERVE | S0 = default-3g | S0 = default-3g |
| 5B | `@ssd_hierarchy_lifetime` | 8 | PREFETCH/PRESERVE × two KEEP/TRANSFER rematerialize | S0 = default-3g | S0 = default-3g |
| 5C | `@ssd_ntile_pipeline` | 4 | two independent PREFETCH/PRESERVE | S0 = default-3g | S0 = default-3g |
| 5D | `@ssd_loop_pipeline` | 4 | PREFETCH/PRESERVE × loop-invariant KEEP | S0 = default-3g | S0 = default-3g |

```text
5A  |F|=2   2/2 × 4090 + 2/2 × 910B   diverge=no
5B  |F|=8   8/8 × 4090 + 8/8 × 910B   diverge=no
5C  |F|=4   4/4 × 4090 + 4/4 × 910B   diverge=no
5D  |F|=4   4/4 × 4090 + 4/4 × 910B   diverge=no
```

The four cuts are structurally different. 5B KEEP is
rematerialize-after-compute. 5C KEEP is not in \(F\).
5D KEEP is the loop-invariant prologue replica that stays
live across `scf.for` while `compute(i) || prefetch(i+1)`.
None of these was a re-skin of another.

```text
measurement cannot expand F
measure all legal inhabitants
do not invent S4
do not drop S0
do not retune n / k / trip
```

3J `T_evi/T_seq` remains PREFETCH vs PRESERVE with KEEP
fixed on. Those logs are not this campaign and were not
overwritten.

## Honest result

```text
measured winner == default-3g
```

once on every existing enumerated Storage \(F\) and on both
devices. `diverge=no` does **not** mean measured ranking is
vacuous. It means the historical inhabitant was also the
fastest legal inhabitant of those \(F\). Device-internal
order may still differ (5C 4090 vs 910B S1/S2). Absolute
μs are not compared across devices and are not FileChecked.

Design hypotheses (copy-engine contention, prefetch×KEEP
joint occupancy) stayed hypotheses. The tables did not
promote them to hardware facts.

```text
#69              unchanged
cost-v04         frozen
default-3g       unchanged
F(program)       unchanged
rewrite license  unchanged
4B chain def     unchanged
```

## 5E is not opened

```text
5E   measured winner → rewrite → HB → runtime A/B
```

opens only on a **real** `diverge=yes` from
`policy=measured-storage-v1` on some later enumerated \(F\).
The current campaign did not produce that. Do **not**
write a rewrite license from `diverge=no`. Do **not**
flatten `C||Storage`. Do **not** invent sibling `sched.wait`.

## What is still open (architecture, not another 5-cut)

Phase 6A turns this campaign into a stable compiler path:
[`storage-production-6a.md`](storage-production-6a.md).
Capacity-aware residency is **6B**, later.

The remaining long-term question is **not** “find a workload that
diverges.” It is which production object this campaign
becomes after 6A:

```text
A. new Storage problem class / new candidate family
   (a later F that is not a retune of 5A–5D)
B. stable production path of the already-verified
   measured ranking + profile + evidence ledger + scheduler
```

Either choice is a later human design. This freeze does
not pick A or B and does not implement either.

## Out of scope

```text
opening 5E
re-measuring frozen 5A / 5B / 5C / 5D sets
retuning n / k / trip to manufacture diverge=yes
inventing a fifth schedule or a new enumerator on current IR
applying default-3g as if it were a measured rewrite
changing cost-v04 / --s2c2-argmin / Score_3
retargeting default-3g
overwriting #69
overwriting 3J loop wall-clock
FileCheck of microseconds
comparing 4090 μs to 910B μs
C||Storage flatten
invented sibling sched.wait
```
