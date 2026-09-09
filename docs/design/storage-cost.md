# Storage Cost Ranking (Phase 4D)

**Status:** **FROZEN** (coincide witness `#92`). Rank a
**fully enumerated** \(F(\text{program})\) under `policy=cost-v04`.
Do **not** add more structural ticks. A later divergence requires
a **new measured-cost policy**, not another heuristic. Cost does
**not** invent members of \(F\), does **not** decide legality, does
**not** replace `default-3g`, and does **not** rank a truncated
product. Frozen `--s2c2-cost` / `--s2c2-argmin` / Score_3 stay
untouched. Not a new Capability grid. Does **not** flatten
`C||Storage`, overwrite `#69`, change the 4B chain definition, or
FileCheck microseconds.

4C entry:
[`storage-global.md`](storage-global.md).

```text
complete F(program)          ← only when enumerated
        ↓
ArgMin ticks (policy=cost-v04)
        ↓
ranked inhabitant
default-3g selected stays the historical tuple
```

```text
Legality   ≠  Selection  ≠  Cost
F(program) ≠  a 64-prefix
cost-v04   ≠  default-3g
cost-v04   ≠  --s2c2-argmin ArgMin_F
cost-v04   ≠  Score_3
ranking    ≠  rewrite license
ranking    ≠  new Capability measurement
```

## Why this cut

4C named \(F(\text{program})\) and kept `default-3g` as the
historical inhabitant. Cost may now **rank** that set. It must
not become a second legality oracle and must not retarget
`default-3g`.

```text
product ≤ 64  →  rank the enumerated members
product > 64  →  ranked=not-enumerated
              →  do not score a truncated prefix
```

## Ticks

Structural ticks over actions already in \(F\). Not hardware
microseconds and not frozen Score_3.

| Action | Tick | When |
| ------ | ---- | ---- |
| `PREFETCH` | 0 | overlap inhabitant |
| `PRESERVE` | 1 | no overlap claim |
| `KEEP_RESIDENCY` | 0 | reuse inhabitant |
| rematerialize `TRANSFER` | 1 | site \(F\) also contains `KEEP_RESIDENCY` |
| singleton `MATERIALIZE` / `TRANSFER` | 0 | no alternative in \(F\) |

```text
score(S) = Σ ticks(action)
ranked   ∈ ArgMin_{S ∈ F(program)} score(S)
```

Among ArgMin ties, display the historical `default-3g` tuple when
it is a minimum. `ranked-eq-default-3g=yes` means the historical
tuple is in ArgMin, not that Cost became `default-3g`.

Unknown still cannot add `PREFETCH` to \(F\), so Cost cannot
rank it in.

## Witness

4090 `@ssd_hierarchy_lifetime`, product=8:

```text
ranked=
  MATERIALIZE //
  MATERIALIZE //
  MATERIALIZE|TRANSFER //
  PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
score=0
ranked-eq-default-3g=yes
argmin-size=1
```

Unknown: last segment `PRESERVE|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY`.
No `PREFETCH` candidate.

`@seven_binary_chains` product=128:

```text
ranked=not-enumerated score=n/a truncated=yes
```

No `hierarchy-global-cost-candidate` dump. Not a 64-prefix ranking.

## Coincide with default-3g

On every **enumerated** Storage fixture currently in tree,
`policy=cost-v04` ArgMin **is** the historical `default-3g`
tuple (`diverge=no`, `argmin-size=1`):

| Workload | Profile | product | diverge |
| -------- | ------- | ------- | ------- |
| `@ssd_hierarchy_lifetime` | 4090 / 910B | 8 | no |
| `@ssd_hierarchy_lifetime` | unknown | 4 | no |
| N-tile hierarchy | 4090 | 4 | no |
| `scf.for` loop hierarchy | 4090 | 4 | no |
| storage-aware pipeline | 4090 | 2 | no |
| `A B A` interleave | 4090 | 1 | no |
| `@seven_binary_chains` | 4090 | 128 truncated | n/a |

This is not a hardware result. `default-3g` prefers
`PREFETCH` / `KEEP_RESIDENCY` whenever those actions are in
\(F(\text{site})\), and those are exactly the 0-tick actions.
Therefore the historical tuple is the unique structural ArgMin
whenever it inhabits enumerated \(F(\text{program})\).

```text
diverge=no
    ≠  Cost became default-3g
    =  current ticks pick the same inhabitant as 3G
runtime correlation
    =  not applicable (no second legal schedule to time)
new Cost dimensions
    =  not this cut
```

A later **measured** cost table is a new policy. It must still
rank only enumerated \(F\), must not invent members, and must
not retarget `default-3g`. Do not FileCheck microseconds here.

## Frozen

`#92` freezes this structural-ranking stage. Do not add ticks
or another heuristic objective.

```text
structural cost-v04     FROZEN
diverge=no on current F FROZEN witness
next Cost cut           measured-cost policy (new name)
                        or leave Cost frozen
```

```text
no divergence  ≠  two policies are the same object
structural     ≠  runtime cost
```

## Policy

```text
policy = cost-v04
ranked ∈ F(program) when enumerated
default-3g selected = historical tuple (unchanged)
Cost Search / --s2c2-argmin = frozen
Capability grid = unchanged
```

## Out of scope

```text
more structural ticks / heuristic knobs
measured-cost policy (new name, later)
new 4090 / 910B Capability measurements
wrapping structural ticks as wall-clock
FileCheck of microseconds
changing --s2c2-cost / --s2c2-cost-hb / --s2c2-cost-cp numbers
changing --s2c2-argmin / --s2c2-walk
retargeting default-3g
changing the 4B chain definition
overwriting #69
C||Storage flatten
invented sibling sched.wait
```
