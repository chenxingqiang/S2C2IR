# ArgMin_F / Pareto_F listing pass (v0.4.4)

Status: **v0.4.4 frozen**. Prints set-valued `ArgMin_F` and `Pareto_F`
over already-listed `Enum_F = R ∩ F`. Does not pick a unique `M*`,
rewrite `P`, treat `π` as a search variable, or change Cost / HB.

```text
ArgMin_F  = argmin_{M ∈ Enum_F} Score_3(M).total
Pareto_F  = Pareto(Enum_F) over (T_HB, C_contention, C_capacity)
```

```text
--s2c2-argmin
--s2c2-argmin=scheds=...,maps=...,devices=...
```

Empty fields use `F_0`. Requested labels are intersected with `F_0`
and emitted in `F_0` declaration order (same helpers as
`--s2c2-enumerate`). Unknown labels fail the pass. Because the pass
does not rewrite `P`, every scored `M` has `HB_M = HB_source`.

`IsLegal` is `isLegalRealization`. `Score_3` is shared
`computeScore3` (frozen v0.3). `sched` / `spaceMap` do not change the
number; distinct maps at the same device are ties.

ArgMin is a **set**. Ties stay ties. `total` is not a fourth Pareto
objective. This is not a heuristic searcher and not Placement.

Does **not** print `π`, `winner=`, or a collapsed unique `M*`.
`--s2c2-argmin` **is** `Search_F(ArgMin)` / `Search_F(Pareto)`
([`search-selection.md`](search-selection.md), v0.4.5). It does not
generate realizations outside `Enum_F`.
