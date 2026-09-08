# Storage Joint Candidate Scheduling (Phase 4B)

**Status:** enumerate the legal joint set \(F(\text{chain})\) over
consecutive storage sites of **one object**, then select the
**default-3G tuple**. Cost does **not** rank, license, or decide
legality. `default-3g` is **frozen**: it only reproduces the
historical 3G combination. Not Cost v0.4. Does **not** flatten
`C||Storage`, densify Capability matrices, overwrite `#69`, or
expand loop-carried alias analysis.

4A entry:
[`storage-schedule.md`](storage-schedule.md).

```text
independent F(site) select
    →
F(chain) ⊆ compatible product of F(site_i)
    →
select one joint inhabitant (policy=default-3g)
```

```text
selection  ≠  rewrite license
selection  ≠  Cost ranking
selection  ≠  proven lifetime fact
F(chain)   ≠  arbitrary rewrite set
default-3g ≠  implicit performance policy
```

## Why this cut

4A gave Cost the wrong grain: a per-site action. Ranking
`PREFETCH` at site 4 independently of `KEEP_RESIDENCY` at site 6
is not a schedule. 4B names the schedule object:

```text
chain(object) = consecutive storage sites of that object
F(chain)      = compatible assignments, one action per site
```

Later Cost may rank \(F(\text{chain})\) under `policy=cost-v04`.
It must not invent members of \(F\) and must not change
`default-3g`.

## Chain

Sites that share object identity, in program order. Interleaved
objects do **not** form one chain.

Witness `@ssd_hierarchy_lifetime`:

```text
chain object=0  sites=0,2,3
chain object=1  sites=1,4,5,6,7
```

## Compatibility

An assignment is in \(F(\text{chain})\) only if each coordinate
is in \(F(\text{site})\) and:

```text
KEEP_RESIDENCY(dst) requires a prior selected action
on the same object that produced dst
```

`MATERIALIZE` / `PREFETCH` / `TRANSFER` / `PRESERVE` all still
execute the as-written movement, so they **produce** `dst`.
`PRESERVE` does not skip the transfer. This filter does not add
actions, flatten `C||Storage`, or invent `sched.wait`.

On the 4090 witness the filtered product is:

```text
object=1  |F(chain)|=8
program   |F| = 1 × 8 = 8
```

Unknown cannot add `PREFETCH`, so:

```text
object=1  |F(chain)|=4
program   |F| = 4
```

## Policy

```text
policy = default-3g
selected ∈ F(chain)
selected = historical 3G tuple
Cost = unchanged
```

`default-3g` reproduces the 4A per-site 3G choices as one
assignment. Do **not** retarget it when Cost arrives. Add
`policy=cost-v04` instead.

Selecting `KEEP_RESIDENCY` on a chain is still not a rewrite.
Reuse remains Phase 3H/3I proven live replica.

## Out of scope

```text
Cost v0.4 ranking / policy=cost-v04
changing the meaning of default-3g
new 4090 / 910B Capability grid points
overwriting #69
C||Storage flatten
invented sibling sched.wait
arbitrary runtime-N / alias-complete overwrite
cross-object global search
changing the 3J wall-clock logs
```
