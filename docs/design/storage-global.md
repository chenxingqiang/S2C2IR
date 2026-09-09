# Storage Global Schedule (Phase 4C)

**Status:** compose the legal global set \(F(\text{program})\) as
the product of frozen \(F(\text{chain})\) in program order **when
that product is fully enumerated**, then select the **default-3G
tuple**. A product larger than 64 is **not** \(F(\text{program})\)
and must not be reported as `legal`. Cost does **not** rank,
license, or decide legality. Does **not** change the 4B chain
definition. `default-3g` is **frozen**. Not Cost v0.4. Does **not**
flatten `C||Storage`, densify Capability matrices, overwrite `#69`,
or expand loop-carried alias analysis.

4B entry:
[`storage-joint.md`](storage-joint.md).

```text
F(chain) select
    →
product size ≤ 64  →  enumerate F(program) ⊆ ∏ F(chain_i)
product size > 64  →  not-enumerated (not a truncated legal set)
    →
select one global inhabitant (policy=default-3g)
    or fail if the historical tuple is not in F
```

```text
selection     ≠  rewrite license
selection     ≠  Cost ranking
F(program)    ≠  arbitrary rewrite set
F(program)    ≠  a silently truncated prefix
chain         =  frozen contiguous run
default-3g    ≠  implicit performance policy
default-3g    ≠  fallback to an arbitrary first tuple
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

`legal=N` is only printed when \(F(\text{program})\) was fully
enumerated. If \(\prod_i |F(\text{chain}_i)| > 64\):

```text
enumerated=no
truncated=yes
legal=not-enumerated
```

The compiler still checks that the historical 3G tuple is a
per-chain inhabitant. It does **not** publish the first 64
tuples as `legal`. Later Cost must not rank a truncated prefix
as if it were the complete set.

Later Cost ranks a **fully enumerated** \(F(\text{program})\)
under `policy=cost-v04`. See
[`storage-cost.md`](storage-cost.md). It must not invent members
of \(F\), must not rank a truncated prefix, and must not change
`default-3g` or the chain definition.

## Witness

`@ssd_hierarchy_lifetime` has four contiguous chains. 4090:

```text
F(program) product=8 enumerated=yes truncated=no legal=8
selected=
  MATERIALIZE //
  MATERIALIZE //
  MATERIALIZE|TRANSFER //
  PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
```

Unknown cannot add `PREFETCH`:

```text
F(program) product=4 enumerated=yes truncated=no legal=4
selected= ... // PRESERVE|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
```

Seven sequential rematerialize chains (`@seven_binary_chains`)
have product \(2^7 = 128\):

```text
enumerated=no truncated=yes legal=not-enumerated
selected-in-legal=yes
```

No `hierarchy-global-candidate` lines. Not `legal=64`.

## Policy

```text
policy = default-3g
selected = historical per-chain 3G tuple
if the historical tuple is not in F:
    report hierarchy-global-error historical-tuple-not-in-F
    fail the pass
    do not substitute legal.front()
chain definition = frozen
Cost = unchanged
```

When the product is not enumerated, `selected-in-legal=yes`
means the historical tuple is a per-chain inhabitant of
\(\prod F(\text{chain}_i)\), not membership in a 64-prefix.

## Out of scope

```text
changing the meaning of default-3g
changing the 4B chain definition
new 4090 / 910B Capability grid points
overwriting #69
C||Storage flatten
invented sibling sched.wait
arbitrary runtime-N / alias-complete overwrite
changing the 3J wall-clock logs
```

Phase 4D ranking is **FROZEN** at `#92`:
[`storage-cost.md`](storage-cost.md).
