# Realization Transformation (v0.5.0)

Status: **v0.5.0 frozen**. Opens `P ↦ P'` as a **program** map,
not a new search inhabitant. Search (v0.4.5–v0.4.12), Cost, HB
axioms, and `R` remain frozen. Merged as `40589a1` (`#37`).

```text
T : P → P' ∪ {⊥}
T(P) ≠ ⊥  ⇒  HB(P') = HB(P)
X'        = Enum_F(P', D)     // rebuilt, never reused
M' ∈ R(P', D)  ⇔  IsLegal(P', D, M') ∧ HB_{M'} = HB(P')
```

This layer does **not** add `--s2c2-search`, beam, a third `Nxt`,
or Token / Concurrent / Pipeline rewrite.

```text
--s2c2-xform
--s2c2-xform=kind=id
```

`kind=id` is the only inhabitant: `P' = P`. Then `HB(P') = HB(P)`
holds by construction, and `X'` is re-enumerated with the same
`isLegalRealization` oracle. Later kinds must *re-prove* HB
equality; they are not this PR.

---

## 1. Why this is not Search

v0.4 walks a fixed program:

```text
X(P, D; F) = Enum_F(P)
Neighbor_F ⊆ F
```

A walk step never changes `P`. If a later rewrite changes the
program, v0.4.6 says: **stop**. Rebuild `X(P', D; F)`.

So:

```text
T  ≠  Neighbor
T  ≠  Nxt
T  ≠  Acc
Search walks X(P); it does not apply T
```

`--s2c2-walk` is unchanged.

---

## 2. The gate

```text
HB(P') = HB(P)
```

is **equality**, not refinement. Concurrent → Pipeline adds
StageOrder, so

```text
HB(P_pipe) ≠ HB(P_conc)     ⇒     Concurrent→Pipeline ∉ T
```

`HB_source ⊆ HB_impl` remains a **lowering** condition, not a
legal `T`. Identity does not lower.

After a successful `T`:

```text
X' = { M | IsLegal(P', D, M) ∧ M ∈ F }
```

Old `Enum_F(P)` is discarded (K10).

---

## 3. Identity inhabitant

```text
T_id(P) = P
hb-eq   = 1
x-rebuilt = |Enum_F(P)|     // same count as --s2c2-enumerate
```

IR is not rewritten. `π` is not printed. Cost numbers are not
redefined.

---

## 4. Out of scope

```text
--s2c2-search
kind ≠ id
Concurrent → Pipeline
Token / StageOrder / SoftPipe rewrites
residency placement
changing Cost / HB axioms / Neighbor / Nxt
P ↦ P' search (walking a space of programs)
IREE / StableHLO / MPI
```
