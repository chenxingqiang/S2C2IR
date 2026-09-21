# F_storage_schedule family (design only)

**Status:** DESIGN FREEZE from `3b46bea`. Not implemented.
Not a rewrite. Not `sufficient=yes`. Not can-run-plan.
Does not reopen 4C, 5A–6B, or 6C-B–L.

```text
Goal     name the joint storage-schedule family
Not      inhabit it, rank it, license it, or rewrite IR
Rewrite  still only from an existing capability license
```

```text
BASELINE = 3b46bea
TYPE     = design freeze
IMPLEMENTATION = CLOSED
```

Healthcheck already said this family is the later opportunity
after 6C-L, not the next implementation cut.

## Why a family, not a sufficient AND

The product axes are these five. Each is a separate
capability today. Folding them into one boolean or one
rewrite would hide which axis failed and reopen 6C-M.

```text
prefetch distance
buffer depth
residency lifetime
eviction / restore
pipeline overlap
```

`F_capacity` is not one of those axes. It is the frozen
tile-count occupancy constraint (`size=1`, `peak-live=3`,
`capacity=2`). It is not byte-level capacity and not an
allocator. A schedule-family member is not legal unless
that constraint already holds. Holding it does not put
the member into the family, and it does not license a
rewrite.

The healthcheck one-liner
`prefetch × depth × residency × capacity` names the later
opportunity. The word `capacity` in that line is this
constraint, not a sixth product axis.

```text
F_capacity              tile-count constraint         FROZEN, not an axis
F(site)/F(chain)/F(program)  storage actions          FROZEN
F_storage_schedule      product of the five axes      this page
sufficient              no
rewrite-license         no
```

## Definition (design)

```text
F_storage_schedule ⊆ product of already-legal sets
```

Each axis keeps its own evidence, applicability, and
constraint facts. The family is a **declared product**,
not a new generation operator and not a Search step
that invents M' outside Enum_F.

```text
member of F_storage_schedule
    !=  realization_claim.v1
    !=  can-run-plan=yes
    !=  Check(r, L) all-satisfy
    !=  rewrite-license=yes
```

Check remains Claim × Legality Fact per-kind compatibility.
A schedule-family member is not automatically a claim.

## Target axes

```text
F_capacity
        frozen tile-count constraint
        not a product axis
F_storage_schedule
        prefetch distance
        buffer depth
        residency lifetime
        eviction / restore
        pipeline overlap
        named, still uninhabited
        sufficient=no
        rewrite-license=no
```

Reuse Evidence / Applicability / F / policy / license.
Do **not** reopen:

```text
4C F(program) product
5A-6B measured campaign / Evidence DB identity
6C-B-L occupancy / restore / dest-invalidation
cost-v04 / default-3g / #69
```

## Forbidden now

```text
implementation / enumerator / s2c2-opt flag
rewrite-license=yes / rewrite-path=yes
sufficient=yes / Decision.subject=sufficient
LiveBytes(t) pretending F_capacity is an allocator
AND of usable ∧ applicable ∧ dest-invalidation ∧ …
IR witness smuggled into Check
heuristic --s2c2-search
frontend / new vendor campaign
FileCheck of microseconds
```

## Later (not this freeze)

```text
propose → review → freeze → verbal 开工
```

only for an inhabitant that lists a **finite** product
without ranking, licensing, or rewriting. Measured
evidence, ArgMin, license, and rewrite stay after that
inhabitant exists.

## Tests

Design claims only. No host. No pass.

| ID | Claim |
| -- | ----- |
| FSS-1 | `F_storage_schedule` is a named product, not a rewrite F |
| FSS-2 | each axis stays independent; no sufficient AND |
| FSS-3 | a family member is not a `realization_claim` and not can-run-plan |
| FSS-4 | 4C / 5A-6B / 6C-B-L remain frozen |
| FSS-5 | no implementation in this cut |
