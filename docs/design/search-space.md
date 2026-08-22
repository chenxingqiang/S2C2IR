# Search Space, Neighbor, Legality (v0.4.5)

Status: **v0.4.5 frozen**. Defines three objects only. Does not pick
beam / hill-climbing / enumerative / Pareto-exploration *as an
algorithm*, does not add `--s2c2-search`, and does not rewrite `P`.
Cost v0.1–v0.3, HB, `R`, `Enum_F`, and set-valued `ArgMin_F` /
`Pareto_F` remain frozen. Baseline: `80944e3`.

```text
v0.4.0  R(P, D)                                FROZEN
v0.4.1  ArgMin / Pareto over R                 FROZEN in search-pareto.md
v0.4.2  Realization Enumerator                 FROZEN in realization-enumerator.md
v0.4.3  listing `--s2c2-enumerate`             FROZEN in realization-enumerator-pass.md
v0.4.4  listing `--s2c2-argmin`                FROZEN in realization-argmin-pass.md
v0.4.5  Search Space / Neighbor / Legality     this document
v0.4.6  Search Algorithm Contract              in search-algorithm-contract.md
v0.4.7+ algorithm pass / rewrite generators    later
```

```text
SearchSpace ≠ Neighbor
Neighbor    ≠ LegalNeighbor
Neighbor    ⇏  R
Accept      ⇒  R
π           ∉ M
ArgMin_F    is a set, not a neighborhood
HB_M        = HB_source                       membership of R
```

---

## 1. Why this layer exists

`F_0` plus `--s2c2-enumerate` / `--s2c2-argmin` already close

```text
F → IsLegal → Enum_F = R ∩ F → ArgMin_F / Pareto_F
```

That is **batch optimization on a listed set**. It does not yet say
what a *step* is. Two models look similar until the neighborhood is
named:

```text
(A) Closed-set selection
    Search(P, D, F) ⊆ Enum_F
    enumeration + optimization
    no new realization

(B) Realization transformation
    M  →  Neighbor(M)  →  legal M'  →  Cost
    explore { M' | M' ∈ R(P, D) }
```

Today's `F_0` implements (A). (B) is the shape of a compiler search
over realizations. This document does **not** choose an algorithm
for (B). It freezes the objects any later algorithm must use.

---

## 2. Search Space

Split ambient coordinates from feasible solutions.

```text
M           = (sched, spaceMap, device)
F           = Sched_F × Maps_F × Dev_F
Ambient(F)  = F
Feasible(P, D; F) = R(P, D) ∩ F = Enum_F
```

**Search Space** (what a searcher may *return* or *score as a
solution*) is the feasible set:

```text
X(P, D; F)  = Feasible(P, D; F) = Enum_F
X(P, D; F)  ⊆ R(P, D)
X(P, D; F)  ⊆ Ambient(F)
```

`R(P, D)` itself is not the working search space: `spaceMap` ranges
over integer maps, so `R` is not a finite syntactic set. `F` is not
the search space either: most of `F_0` fails `IsLegal`
(`|F_0|=24`, `|Enum_{F_0}|=8` on the r4 fixture).

```text
Ambient(F)          generate / flip coordinates here
X = Enum_F          return / score solutions here
R(P, D)             semantic universe (may be larger than F)
```

`π` is not a coordinate of `X`. Expanding `F` to a declared `F'`
is family extension (v0.4.2), then `X` becomes `Enum_{F'}`.

`X` is relative to a **fixed** `P`. A later rewrite generator that
produces `P' ≠ P` must re-form `X(P', D; F)`; it does not keep the
old `Enum_F` as its feasible set. `D` in this layer is the declared
`Dev_F` axis, not a second hidden filter on top of `IsLegal`.

A search *path* starts in `X`. `Neighbor` is still defined on every
`M ∈ F`, including illegal coordinates, so generate-then-filter
can name a failed flip. The walk itself does not start there.

---

## 3. Neighbor(M)

`Neighbor` is a parameter of the search *problem*, not of Cost or HB.

```text
Neighbor_F : Ambient(F) → 𝒫(Ambient(F))
Neighbor_F(M) ⊆ F
```

### The implication that this layer decides

```text
M' ∈ Neighbor_F(M)  ⇏  M' ∈ R(P, D)
M' ∈ Neighbor_F(M)  ⇒  M' ∈ Ambient(F)
```

Neighbors are **candidates**. They are generated first, then
filtered. `Neighbor` must not embed `IsLegal` or rebuild HB. The
shared oracle stays `isLegalRealization`.

### Two canonical coordinate neighborhoods

`M` is a 3-tuple. Hamming distance counts how many axes differ.

```text
N_all(M) = F
N_1(M)   = { M' ∈ F | d_H(M, M') = 1 }
```

```text
M ∈ N_all(M)
M ∉ N_1(M)
```

`N_all` is the closed-set / enumerative neighborhood: every declared
coordinate is a neighbor of every `M`, including `M` itself. Batch
`ArgMin_F` / `Pareto_F` is optimization on `X` with implicit `N_all`
(no path is required). A local step does not use the self-neighbor.

`N_1` is the local *coordinate* transformation: change exactly one
of `sched`, `spaceMap`, `device`. On `F_0`,

```text
|N_1(M)| = (|Sched_F0|-1) + (|Maps_F0|-1) + (|Dev_F0|-1)
         = 2 + 1 + 3
         = 6
```

Example, `M = (cpu-seq, default, cpu)`:

```text
N_1(M) =
  (gpu-async,      default, cpu)     // illegal pairing
  (npu-staged-dma, default, cpu)     // illegal pairing
  (cpu-seq,        t5,      cpu)     // legal
  (cpu-seq,        default, gpu)     // illegal pairing
  (cpu-seq,        default, npu)     // illegal pairing
  (cpu-seq,        default, cim)     // legal
```

A later algorithm may use `N_all`, `N_1`, or another function
`N : F → 𝒫(F)`. It may not silently grow `F`.

### What Neighbor is not

```text
not a rewrite of Token / Concurrent / Pipeline
not a new Cost
not a π-neighborhood of linear extensions
not Placement of residencies
not “any MLIR pass that happens to typecheck”
```

An IR-rewrite generator, if added later, is a *different*
`Neighbor` that still lands in some ambient set and is still
filtered by §4. Concurrent → Pipeline is already ∉ `R`, so it
cannot be a legal step. This document does not list rewrite
generators.

---

## 4. Legality Preservation

Two predicates, not one.

```text
IsLegal(P, D, M)     shared capability oracle          (T1/T2/T3)
HB_M = HB_source     semantic realization membership
R(P, D) = { M | IsLegal(P, D, M) ∧ HB_M = HB_source }
```

```text
LegalNeighbor_F(P, D, M) = Neighbor_F(M) ∩ R(P, D)
                         = Neighbor_F(M) ∩ Enum_F
```

### The implication that *does* hold

```text
M' ∈ LegalNeighbor_F(P, D, M)  ⇒  M' ∈ R(P, D)
                               ⇒  M' ∈ X(P, D; F)
```

Search may **emit** members of `Neighbor_F(M)`.
Search may **accept, step to, or score** only members of
`LegalNeighbor_F(P, D, M)`.

Illegal candidates are discarded. They are not written back into
S²C² HB. They do not receive a `Score_3` that could leak into
`ArgMin_F`.

### Coordinate neighbors vs rewrite neighbors

For `N_all` / `N_1` the program `P` is unchanged, so

```text
HB_M' = HB_source
```

holds by construction (non-rewriting consumer). The filter that
actually rejects members of `N_1` is `IsLegal` (profile pairing).

If a later rewrite-`Neighbor` changes `P` to `P'`, construction
invariance is gone. That generator must *re-prove*

```text
HB(P') = HB(P) ∧ IsLegal(P', D, M')
```

before the step is legal. `HB_source ⊆ HB_impl` remains a lowering
condition, not a Search step.

### Why not `Neighbor ⊆ R`

Closing `Neighbor` inside `R` would make `Neighbor` depend on
`(P, D)` and hide the oracle inside the generator. That grows a
second legality matrix and cannot express “this flip is a candidate
that failed IsLegal”. Generate-then-filter keeps:

```text
F  →  Neighbor  →  IsLegal ∧ HB  →  LegalNeighbor ⊆ X
```

aligned with the already-frozen

```text
F  →  IsLegal  →  Enum_F
```

---

## 5. How (A) and (B) sit on the same objects

```text
Closed-set (A)     X = Enum_F,   Neighbor = N_all
                   ArgMin_F / Pareto_F already compute on X
                   no path, no new M

Local tuple (B₀)   X = Enum_F,   Neighbor = N_1
                   steps are LegalNeighbor = N_1 ∩ Enum_F
                   still no new label outside F
                   still no IR rewrite

Rewrite (B₁)       later generator, same X-filter
                   Accept ⇒ R, else discard
```

(A) is not a competing math. It is `N_all` plus batch
optimization. `--s2c2-argmin` stays that layer. A later local
searcher would be the first consumer of `N_1`. Neither is
implemented in this PR.

On frozen Score_3, `LegalNeighbor` still only *changes the number*
when `device` changes (and the pairing stays legal). `sched` /
`spaceMap` flips at the same device stay distinct ties. That is a
Cost fact, not a reason to shrink `Neighbor`.

---

## 6. Out of scope

```text
beam / hill-climbing / simulated annealing / ILP
--s2c2-search
unique M* on ArgMin ties
Cost depending on sched / spaceMap
π as a search coordinate
undeclared F' grown inside Neighbor
Token / Concurrent / Pipeline rewrite generators
residency placement
IREE / StableHLO / MPI / CUDA / NPU ISA
```

---

## 7. Tests

Design claims only. No new pass. Existing L1–L4 / A1–A6 / S3 remain
the witnesses.

| ID | Claim |
| -- | ----- |
| K1 | Search Space `X = Enum_F`, not `F` and not all of `R` |
| K2 | `M' ∈ Neighbor(M) ⇏ M' ∈ R`; `M' ∈ Neighbor(M) ⇒ M' ∈ F` |
| K3 | `LegalNeighbor = Neighbor ∩ Enum_F`; Accept ⇒ `R` |
| K4 | `N_all(M) = F`; `ArgMin_F` is batch optimization on `X` with implicit `N_all` |
| K5 | `N_1` is Hamming-1 on `F_0`; `|N_1|=6`; example `cpu-seq/default/cpu` has two legal neighbors |
| K6 | illegal `N_1` members are discarded, not scored into `ArgMin_F` |
| K7 | Concurrent → Pipeline ∉ `LegalNeighbor` (S3 / N4) |
| K8 | no algorithm pass; `π` is not a Neighbor axis |
| K9 | `M ∈ N_all(M)` and `M ∉ N_1(M)`; a path starts in `X` |
| K10 | rewrite `P ↦ P'` rebuilds `X(P', D; F)`; it does not keep the old `Enum_F` |
