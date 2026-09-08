# Storage Global Schedule (Phase 4C)

**Status:** compose the legal global set \(F(\text{program})\) as
the product of frozen \(F(\text{chain})\) in program order, then
select the **default-3G tuple**. Cost does **not** rank, license,
or decide legality. Does **not** change the 4B chain definition.
`default-3g` is **frozen**. Not Cost v0.4. Does **not** flatten
`C||Storage`, densify Capability matrices, overwrite `#69`, or
expand loop-carried alias analysis.

4B entry:
[`storage-joint.md`](storage-joint.md).

```text
F(chain) select
    →
F(program) ⊆ product of F(chain_i)
    →
select one global inhabitant (policy=default-3g)
```

```text
selection     ≠  rewrite license
selection     ≠  Cost ranking
F(program)    ≠  arbitrary rewrite set
chain         =  frozen contiguous run
default-3g    ≠  implicit performance policy
```

## Why this cut

4B gave each contiguous object run its own \(F(\text{chain})\).
A program still has **several** chains. Cost ranking one chain
in isolation is not a program schedule. 4C names that object:

```text
S ∈ F(program) ⊆ ∏_i F(chain_i)
```

Members are taken only from existing \(F(\text{chain})\). This
layer does **not** splice interleaved objects back together
and does **not** invent actions.

Later Cost may rank \(F(\text{program})\) under
`policy=cost-v04`. It must not invent members of \(F\) and must
not change `default-3g` or the chain definition.

## Witness

`@ssd_hierarchy_lifetime` has four contiguous chains. 4090:

```text
F(program) legal=8
selected=
  MATERIALIZE //
  MATERIALIZE //
  MATERIALIZE|TRANSFER //
  PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
```

Unknown cannot add `PREFETCH`:

```text
F(program) legal=4
selected= ... // PRESERVE|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
```

## Policy

```text
policy = default-3g
selected ∈ F(program)
selected = historical per-chain 3G tuple
chain definition = frozen
Cost = unchanged
```

## Out of scope

```text
Cost v0.4 ranking / policy=cost-v04
changing the meaning of default-3g
changing the 4B chain definition
new 4090 / 910B Capability grid points
overwriting #69
C||Storage flatten
invented sibling sched.wait
arbitrary runtime-N / alias-complete overwrite
changing the 3J wall-clock logs
```
