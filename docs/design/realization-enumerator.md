# Realization Enumerator (v0.4.2)

Status: **v0.4.2 frozen**. Finite, provably complete listing of
candidates already in frozen `R`. Does not pick `M*`, rewrite `P`,
place residencies, or change Cost / HB / `π`. v0.4.0–v0.4.1 and Cost
v0.1–v0.3 remain frozen.

```text
v0.4.0  R(P, D)                                FROZEN
v0.4.1  ArgMin / Pareto over R                 FROZEN
v0.4.2  Realization Enumerator                 FROZEN (this document)
v0.4.3  listing pass `--s2c2-enumerate`        realization-enumerator-pass.md
v0.4.4+ heuristic searcher / placement         later
```

```text
Enumerator ≠ Searcher
Enumerator ≠ ArgMin
Enumerator ≠ Rewrite
Enumerator ≠ Placement
ArgMin_F ≠ ArgMin_R ∩ F                    in general
π ∉ enumerated tuple
HB_M = HB_source
```

---

## 1. Why this layer exists

Frozen Search defines functions on a set:

```text
ArgMin(P, D) ⊆ R(P, D)
Pareto(R)    ⊆ R(P, D)
```

It does not say how a compiler *lists* the members. A heuristic
searcher would pick without a completeness claim. This layer only
constructs a finite set that is exactly `R` restricted to a declared
family.

```text
Semantics
    ↓
Legality
    ↓
R(P, D)                         frozen
    ↓
F                               finite family (this layer)
    ↓
Enum(P, D; F) = R(P, D) ∩ F
    ↓
ArgMin_F / Pareto_F             restricted to Enum, not ArgMin_R ∩ F
    ↓
placement / rewrite             later
```

---

## 2. Finite family

`R(P, D)` has a finite `sched` / `device` product, but `spaceMap`
ranges over integer maps, which is not a finite syntactic set. This
layer does **not** enumerate all maps. It enumerates a declared finite
family `F`:

```text
F = Sched_F × Maps_F × Dev_F
M = (sched, spaceMap, device) ∈ F
```

v0.4.2 default family `F_0` (already-selectable compilers axes):

```text
Sched_F0 = { cpu-seq, gpu-async, npu-staged-dma }
Maps_F0  = { default, t5 }
Dev_F0   = { cpu, gpu, npu, cim }
```

`default` is the built-in `--convert-stor-to-memref` map.
`t5` is the T5 witness `ssd=100,dram=2,hbm=9`.

A test or invocation may use a smaller family. S1/S2 already fix

```text
D_test = { cpu, gpu }
```

so those fixtures use `Dev_F = D_test`, not all of `Dev_F0`.

Adding a new map or device to `F` is a **family extension**, not a
change to `R` and not Placement.

---

## 3. Enumerator

```text
Enum(P, D; F) =
  { M ∈ F | IsLegal(P, D, M) ∧ HB_M = HB_source }
```

`IsLegal` is the frozen capability predicate. `HB_source` means
`HB(P)`. Concurrent → Pipeline is not in `F` (it is not a `sched`
label) and is not in `R` (`HB_M ≠ HB_source`).

### Completeness (relative to F)

```text
Enum(P, D; F) = R(P, D) ∩ F
```

Proof obligation, not a new axiom:

1. `⊆` — every emitted `M` is in `F` and satisfies the `R` predicate.
2. `⊇` — every `M ∈ R(P, D) ∩ F` is emitted. No extra filter
   (heuristics, lexical IR order, `π`, Cost).

This is completeness **inside `F`**. It is not `Enum = R(P, D)`,
because maps outside `Maps_F` are not generated. Opening those maps
is later Placement.

### What is not enumerated

```text
π
Token / Concurrent / Pipeline rewrites
StageOrder / sibling await
new residencies
weighted / sampled / beam candidates
```

`π = Topo(G_HB; IRRank)` remains a scoring artifact of `(P, HB)`.

---

## 4. Relation to ArgMin / Pareto

Enumerator outputs a set. It does not minimize. Write `Enum_F` for
`Enum(P, D; F)`. Frozen global ArgMin stays:

```text
ArgMin_R(P, D) = argmin_{M ∈ R(P, D)} Score_3(M).total
```

Restricted objectives after enumeration are:

```text
ArgMin_F(P, D) = argmin_{M ∈ Enum_F} Score_3(M).total
               = ArgMin(Enum_F)
Pareto_F(P, D) = { M ∈ Enum_F | no M' ∈ Enum_F : M' ≺ M }
               = Pareto(Enum_F)
```

`ArgMin_F` is ArgMin restricted to the finite candidate family `F`.
It is **not**, in general, `ArgMin_R ∩ F`. The latter can be empty
even when `Enum_F` is nonempty. They coincide only when
`F ⊇ ArgMin_R` (the family covers every global minimum).

Counterexample (N8): `R={A,B,C}` with costs `1,2,3` and `F={B,C}`
gives `ArgMin_R ∩ F = ∅` but `ArgMin_F = {B}`.

On today's Score_3, only `device` changes the number, so members that
differ only by `sched` / `spaceMap` stay ties. That is a frozen Cost
fact, not an excuse to drop those members from `Enum_F`.

---

## 5. Out of scope

```text
--s2c2-search heuristic
picking a unique M* when ArgMin has many members
changing v0.1 / v0.2 / v0.3 scores
redefining HB or R
placement / IR rewrite / auto-scheduling
infinite spaceMap generation
IREE / StableHLO / MPI / CUDA / NPU ISA
```

`--s2c2-enumerate` prints `Enum` on stderr. It must not rewrite `P`.
See [`realization-enumerator-pass.md`](realization-enumerator-pass.md).

---

## 6. Tests

Design claims over existing witnesses. No enumerator pass in this PR.

| ID | Claim |
| -- | ----- |
| N1 | `F_0` is finite: `\|F_0\| = 3 × 2 × 4 = 24` |
| N2 | `Enum(P, D; F) = R(P, D) ∩ F` (no heuristic drop) |
| N3 | R1 / R2 / R3 witnesses are in `Enum` for the `F` that contains them |
| N4 | Concurrent → Pipeline ∉ `F` and ∉ `Enum` |
| N5 | `π` is not a component of any emitted `M` |
| N6 | S1/S2 keep `Dev_F = D_test={cpu,gpu}`; they do not require `Dev_F0` |
| N7 | `Enum_F` keeps every legal member; C6 equal totals stay two members, then `ArgMin_F` may keep both |
| N8 | `R={A,B,C}` costs `1,2,3`, `F={B,C}`: `ArgMin_R ∩ F = ∅` and `ArgMin_F = {B}` |
