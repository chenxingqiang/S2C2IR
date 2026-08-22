# Realization Enumerator listing pass (v0.4.3)

Status: **implementation of frozen v0.4.2**. Prints `Enum_F`. Does not
pick `M*`, rewrite `P`, or change Cost / HB / `π`.

```text
Output(M) = 1  iff  M ∈ R(P, D) ∩ F
```

```text
--s2c2-enumerate
--s2c2-enumerate=scheds=...,maps=...,devices=...
```

Empty fields use `F_0`. Requested labels are intersected with `F_0`
and emitted in `F_0` declaration order (deterministic). Unknown labels
fail the pass. Because the pass does not rewrite `P`, every emitted
`M` has `HB_M = HB_source`.

`IsLegal(P, D, M)` is `isLegalRealization` in
[`S2C2Legality.h`](../../include/s2c2/S2C2Legality.h) (T1/T2/T3
profile pairing). `M ∈ F` is not sufficient. Count is `|R ∩ F|`,
not `|F|`.

Does **not** print Score_3, ArgMin, Pareto, or `π`.
