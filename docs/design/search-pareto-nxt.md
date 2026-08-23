# Pareto-aware Next (v0.4.11)

Status: **v0.4.11 design**. A second inhabitant of frozen `A` that
changes **only** `Nxt`. `N`, `S`, `Rst`, `Acc`, Neighbor, Cost, HB,
and `R` stay as in v0.4.5–v0.4.10. Baseline: `727f0a3` (`#34`).

```text
N        = N_1                 // unchanged
S        = StartFirst          // unchanged
Rst      = StartUnused         // unchanged
Nxt_0    = first(Best)         // v0.4.9 scalar, still the default
Nxt_P    = first(Pareto(Frontier))
Acc      = inline Accept       // unchanged
```

Not `--s2c2-search`, not beam, not `P ↦ P'`, not ArgMin-then-filter.

```text
--s2c2-walk                 // nxt=scalar (frozen v0.4.9)
--s2c2-walk=nxt=pareto      // this inhabitant
```

---

## 1. Why this is a new Nxt, not a filter

v0.4.1 already names batch

```text
Pareto_F = Pareto(Enum_F) over (T_HB, C_contention, C_capacity)
```

That is `N_all` / Complete (`--s2c2-argmin`). It has no path.

A walk inhabitant must still be

```text
Nxt : State → LegalNeighbor(current) ∪ {⊥}
```

so

```text
Nxt_P(State) ∈ Pareto(Frontier(current)) ∪ {⊥}
```

and **not**

```text
first(ArgMin(Frontier)) ∩ Pareto_F
first(Pareto_F)            // that would be StartBest
```

`total` is not a fourth objective.

---

## 2. Pareto of the Frontier

After Generate / Validate / Score (v0.4.6):

```text
Cost⃗(M) = (T_HB, C_contention, C_capacity)
M' ≺ M   ⇔  M' strictly dominates M
Pareto(Frontier) = { M ∈ Frontier | no M' ∈ Frontier : M' ≺ M }
```

Dominance is the shared `strictlyDominates` already used by
`--s2c2-argmin`. Same oracle, no second matrix.

```text
Nxt_P = ⊥                 ⇔  Frontier = ∅
Nxt_P ≠ ⊥                 ⇒  Nxt_P = first(Pareto(Frontier))
                             ∈ Frontier ⊆ X
                             ∉ Accepted
```

`first` is the same `WalkTieBreak` as v0.4.9 (`F_0` product order).
`Pareto(Frontier)` stays a **set**; `Nxt` is one member.

Totality is unchanged: a nonempty Frontier has a nonempty Pareto
front.

---

## 3. Scalar and Pareto can differ

```text
A = (10, 0, 0)     total = 10
B = (0, 0, 6)      total = 6
```

`A` and `B` are incomparable, so `Pareto({A,B}) = {A,B}`.
`first(Best) = B` (min total). `first(Pareto)` follows
`WalkTieBreak`, which need not be `B`.

On frozen `@r4_same_program` / `F_0`, `Cost⃗` varies only by
contention (`T_HB` and capacity are equal). Then domination is
monotone with `total`, so

```text
Nxt_P = Nxt_0
```

on that fixture. The FileCheck trajectory is therefore the same
as W1. That is a device-table fact, not a claim that the two
functions are identical.

---

## 4. Output after the walk

`Nxt_P` does not redefine ArgMin or Pareto on `X`:

```text
Complete     ⇒  ArgMin(Accepted)  = ArgMin_F
                Pareto(Accepted)  = Pareto_F
LocalStop    ⇒  ArgMin(Accepted)  ≠ ArgMin_F   (v0.4.10)
                Pareto(Accepted)  ≠ Pareto_F   in general
```

`--s2c2-walk=nxt=pareto` prints the Pareto set of `Accepted` after
the same Complete / LocalStop labels. Default `nxt=scalar` output
is unchanged.

---

## 5. Out of scope

```text
--s2c2-search
beam / SA / ILP
changing R / HB / Cost / Neighbor / Start / Restart
StartBest / StartRandom
extracting Acc
P ↦ P'
unique M*
π in State
```
