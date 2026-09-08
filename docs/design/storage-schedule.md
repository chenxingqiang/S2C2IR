# Storage Candidate Scheduling (Phase 4A)

**Status:** enumerate the legal action set \(F(\text{site})\), then
select the **default-3G inhabitant**. Cost does **not** rank,
license, or decide legality. Not Cost v0.4. Does **not** flatten
`C||Storage`, densify Capability matrices, overwrite `#69`, or
expand loop-carried alias analysis.

3J entry:
[`storage-loop-wallclock.md`](storage-loop-wallclock.md).

```text
rule-based unique action
    →
legal candidates F(site)
    →
select one inhabitant (policy=default-3g)
```

```text
selection  ≠  rewrite license
selection  ≠  Cost ranking
selection  ≠  proven lifetime fact
F(site)    ≠  arbitrary rewrite set
```

## Why this cut

3G–3J proved one storage realization on hardware. Each site still
had a **single** printed action. A scheduler needs the legal set
first:

```text
What may this site become?
Which inhabitant do we take today?
Cost is not the answer to either question yet.
```

This increment exposes \(F(\text{site})\) and an explicit default
policy that **reproduces** the 3G unique action. Later Cost may
rank \(F\), not invent members of \(F\).

## Legal sets

| Site class | \(F(\text{site})\) | default-3G |
| ---------- | ------------------ | ---------- |
| first `stor.materialize` | `{MATERIALIZE}` | MATERIALIZE |
| first SSD→Host | `{MATERIALIZE}` | MATERIALIZE |
| sequential Host→HBM consume | `{TRANSFER}` | TRANSFER |
| overlap + KEEP evidence | `{PREFETCH, PRESERVE}` | PREFETCH |
| overlap without evidence | `{PRESERVE}` | PRESERVE |
| rematerialize live replica | `{KEEP_RESIDENCY, TRANSFER}` | KEEP_RESIDENCY |

```text
PREFETCH        = authorized KEEP C||Storage (IR stays concurrent)
PRESERVE        = do not claim prefetch
KEEP_RESIDENCY  = intended reuse (apply only if proven)
TRANSFER        = as-written rematerialize / required consume
```

Not in \(F\):

```text
FLATTEN C||Storage
invented sibling sched.wait
alias-incomplete DCE
Cost-invented actions
```

Unknown evidence still **cannot** add PREFETCH to \(F\).

Reuse remains Phase 3H/3I: proven live replica only. Selecting
`KEEP_RESIDENCY` is not itself a rewrite.

## Policy

```text
policy = default-3g
selected ∈ F(site)
Cost = unchanged
```

`default-3g` is the unique 3G inhabitant. It is a **selection
policy**, not a Cost table and not a rewrite license.

## Out of scope

```text
Cost v0.4 ranking
new 4090 / 910B Capability grid points
overwriting #69
C||Storage flatten
arbitrary runtime-N / alias-complete overwrite
changing the 3J wall-clock logs
Phase 4 Cost v0.4 ranking
```
