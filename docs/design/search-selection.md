# Search is selection over Enum_F (v0.4.5)

Status: **v0.4.5 frozen**. Answers one question and stops. Does not
add a heuristic searcher, a unique `M*`, a rewrite of `P`, or a
generator of new space maps. Realization Space v0.4.0, Search math
v0.4.1, Enumerator v0.4.2–v0.4.4, and Cost v0.1–v0.3 remain frozen.

```text
v0.4.0  R(P, D)                                FROZEN
v0.4.1  ArgMin / Pareto over R                 FROZEN in search-pareto.md
v0.4.2  Realization Enumerator                 FROZEN in realization-enumerator.md
v0.4.3  listing `--s2c2-enumerate`             FROZEN in realization-enumerator-pass.md
v0.4.4  listing `--s2c2-argmin`                FROZEN in realization-argmin-pass.md
v0.4.5  Search = selection over Enum_F         FROZEN (this document)
v0.4.6+ family extension / rewrite / placement later
```

```text
Search      ≠ Generation
Search      ≠ FamilyExtension
Search      ≠ Rewrite
Search      ≠ Placement
Enumerator  ≠ Searcher
ArgMin_F    is already the scalar search function
Pareto_F    is already the vector search function
π           ∉ M and ∉ search variables
HB_M        = HB_source
```

---

## 1. The question this layer answers

After `--s2c2-enumerate` and `--s2c2-argmin`, the stack is:

```text
F  →  IsLegal  →  Enum_F = R ∩ F  →  ArgMin_F / Pareto_F
```

The remaining design fork is:

```text
(A)  Search re-selects among already-listed members of Enum_F
(B)  Search may start from some M and produce a new M'
     that was not listed, provided M' ∈ R(P, D)
```

This document freezes **(A)**.

```text
Search_F(Policy) ⊆ Enum_F
```

There is no operator in this layer that invents a realization
outside `Enum_F`.

---

## 2. Why (B) is not Search at this stack tip

`M` is already a finite tuple:

```text
M = (sched, spaceMap, device)
```

`Enum_F` is already complete **inside** the declared family:

```text
Enum_F = R(P, D) ∩ F
```

So any function `T : M ↦ M'` falls into exactly one of three cases.

### Case I — `M' ∈ Enum_F`

`T` only picks or filters already-listed members. That is a
**policy** on a known set:

```text
Policy : 𝒫(Enum_F) → 𝒫(Enum_F)
Policy(S) ⊆ S
```

Frozen policies already exist:

```text
Id        (S) = S                 = Enum_F
ArgMin    (S) = ArgMin(S)         = ArgMin_F
Pareto    (S) = Pareto(S)         = Pareto_F
```

Writing `T(M) = (gpu-async, t5, gpu)` when that triple is already
in `Enum_F` does not create a realization. It re-selects one.

### Case II — `M' ∈ R(P, D)` and `M' ∉ F`

`T` left the declared family. Completeness of the enumerator is
relative to `F`, not to all of `R`:

```text
Enum_F = R ∩ F     ≠     R
```

A new `spaceMap`, `sched` label, or `device` that is not in `F`
is a **family extension** `F ↦ F'`. Then:

```text
Enum_{F'} = R ∩ F'
```

must be re-listed. That is how new maps were already defined in
v0.4.2: adding a map or device to `F` is not a change to `R` and
not Placement. It is also not Search.

Doing this *inside* a searcher would silently drop the
completeness claim (`Enum = R ∩ F`) and invent an incomplete
heuristic over an undeclared `F'`.

### Case III — `T` rewrites `P`

Then the object is no longer a realization tuple. Typical
rewrites add HB:

```text
P:          Concurrent { A, B }
candidate:  Pipeline { A, B }

HB_candidate ≠ HB_source
⇒  candidate ∉ R(P, D)
```

Residency placement, auto-scheduling IR, and Token / Concurrent /
Pipeline edits are **Rewrite / Placement**. They are later, and
they still have to prove `HB_M = HB_source` before the result can
re-enter `R`. This document does not open those axes.

---

## 3. Frozen definition

```text
Search_F(P, D; Policy) = Policy(Enum_F)
Search_F(P, D; Policy) ⊆ Enum_F ⊆ R(P, D)
```

`Policy` is set-valued. Ties stay ties. `M*` remains “any member
of `ArgMin_F`”, not a lexical winner.

```text
Search ≠ “pick one M and mutate its coordinates”
Search = “apply a closed policy to the already-complete list”
```

On today’s frozen Score_3,

```text
Cost(M) = Score_3(P, M.device, HB(P), π(P))
```

so `Policy = ArgMin` / `Pareto` still partitions by **device**
(and legality). Distinct `sched` / `spaceMap` at the same device
remain distinct members and remain score ties. Search must not
deduplicate them, and must not invent a schedule-dependent cost
to break the tie.

`π = Topo(G_HB; IRRank)` is still a scoring artifact of `(P, HB)`.
It is not a coordinate of `M` and not an input to `Policy`.

---

## 4. What this layer does not add

No new compiler pass. `--s2c2-enumerate` and `--s2c2-argmin`
already implement `Id` / `ArgMin` / `Pareto` over `Enum_F`.

A future `--s2c2-search` that reprints `ArgMin_F` would not be a
new mathematical layer. A future `--s2c2-search` that *drops*
members of `Enum_F` by beam / sample / heuristic would reopen
enumerator completeness and is out of scope.

```text
--s2c2-search heuristic
unique winner on ArgMin ties
T : M ↦ M' with M' ∉ Enum_F
undeclared F' grown inside a searcher
rewrite of Token / Concurrent / Pipeline
residency placement
Cost depending on sched / spaceMap
π as a search variable
IREE / StableHLO / MPI / CUDA / NPU ISA
```

---

## 5. Later layers (not this document)

If a later phase wants generation, it must name which case it is:

| Intent | Required object | Re-enters the stack how |
| ------ | ---------------- | ----------------------- |
| new label already in some `F'` | family extension | declare `F'`, run `Enum_{F'}` |
| new IR with the same HB | Rewrite / Placement | prove `HB_M = HB_source` and `IsLegal`, then `M ∈ R` |
| filter of the current list | `Policy` | already this layer |

There is no fourth door named “search transformation” that bypasses
`F` and `HB_M = HB_source`.

---

## 6. Tests

Design claims only. No new pass. Existing A1–A6 / L1–L4 / S1–S6
remain the witnesses.

| ID | Claim |
| -- | ----- |
| Q1 | `Search_F(Policy) ⊆ Enum_F` for `Policy ∈ {Id, ArgMin, Pareto}` |
| Q2 | `T(M)=M'` with `M' ∈ Enum_F` is re-selection, not a new realization |
| Q3 | `M' ∈ R \ F` is family extension (`F ↦ F'`), not Search |
| Q4 | Concurrent → Pipeline rewrites `P` and is ∉ `R` (S3 / N4) |
| Q5 | no `--s2c2-search` heuristic; no unique `M*` |
| Q6 | `π` is not a `Policy` input (S4 / A4) |
| Q7 | same-device `sched` / `spaceMap` stay distinct ties (S6 / A2) |
| Q8 | `--s2c2-argmin` already *is* `Search_F(ArgMin)` and `Search_F(Pareto)` |
