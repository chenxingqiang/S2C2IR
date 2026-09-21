# Search is selection over Enum_F

**Status:** companion lock for [`search-space.md`](search-space.md)
v0.4.5 model (A). Not a new version number. Not `--s2c2-search`.
Not generation. Does not reopen Neighbor, Algorithm, rewrite, or
sufficient.

```text
NUMBERED v0.4.5   = Search Space / Neighbor / Legality
THIS DOCUMENT     = closed-set policy prose for model (A)
```

#28 drafted this as "v0.4.5 Search = selection". That slot was
later taken by Search Space. The claim itself is already frozen:

```text
Search(P, D, F) ⊆ Enum_F
X(P, D; F)      = Enum_F
```

This page only names the **policy** that batch ArgMin already is.

```text
Search      != Generation
Search      != FamilyExtension
Search      != Rewrite
Search      != Placement
Enumerator  != Searcher
ArgMin_F    is already the scalar search function
Pareto_F    is already the vector search function
pi          not in M and not a search variable
HB_M        = HB_source
```

---

## 1. Closed-set policy

After `--s2c2-enumerate` and `--s2c2-argmin`:

```text
F  ->  IsLegal  ->  Enum_F = R ∩ F  ->  ArgMin_F / Pareto_F
```

```text
Search_F(Policy) = Policy(Enum_F)
Search_F(Policy) ⊆ Enum_F ⊆ R(P, D)
```

`Policy` is set-valued. Ties stay ties. `M*` remains "any member
of `ArgMin_F`", not a lexical winner.

Frozen policies already exist:

```text
Id        (S) = S                 = Enum_F
ArgMin    (S) = ArgMin(S)         = ArgMin_F
Pareto    (S) = Pareto(S)         = Pareto_F
```

`--s2c2-argmin` **is** `Search_F(ArgMin)` and `Search_F(Pareto)`.
It does not generate a realization outside `Enum_F`.

---

## 2. Three cases for T : M |-> M'

### Case I — M' in Enum_F

Re-selection. Not a new realization.

### Case II — M' in R(P, D) and not in F

Family extension `F -> F'`. Re-list `Enum_{F'}`. Not Search.

### Case III — T rewrites P

Then HB may change. Concurrent -> Pipeline is not in `R`
(S3 / N4). Rewrite / Placement stay later.

There is no fourth door named "search transformation".

---

## 3. What this page does not add

```text
new version number
--s2c2-search heuristic
unique winner on ArgMin ties
T : M |-> M' with M' not in Enum_F
undeclared F' grown inside a searcher
rewrite of Token / Concurrent / Pipeline
sufficient / can-run-plan / authorization
```

Neighbor and walk algorithms remain
[`search-space.md`](search-space.md) through
[`search-verification.md`](search-verification.md).

---

## 4. Tests

Design claims only. Witnesses stay L1-L4 / A1-A6 / K1-K10 / S3.

| ID | Claim |
| -- | ----- |
| SEL-1 | `Search_F(Policy) ⊆ Enum_F` for `Policy` in {Id, ArgMin, Pareto} |
| SEL-2 | `T(M)=M'` with `M'` in `Enum_F` is re-selection |
| SEL-3 | `M'` in `R \ F` is family extension, not Search |
| SEL-4 | Concurrent -> Pipeline not in `R` (S3 / N4 / K7) |
| SEL-5 | no `--s2c2-search` heuristic; no unique `M*` |
| SEL-6 | `pi` is not a Policy input |
| SEL-7 | same-device `sched` / `spaceMap` stay distinct ties |
| SEL-8 | `--s2c2-argmin` is `Search_F(ArgMin)` and `Search_F(Pareto)` |
