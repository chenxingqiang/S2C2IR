# Restart / Complete coverage (v0.4.10)

Status: **v0.4.10 frozen**. Does **not** inhabit a new `A`. Uses the
frozen v0.4.9 inhabitant as-is:

```text
N   = N_1
S   = StartFirst
Rst = StartUnused
Nxt = first(Best)
```

and only makes the already-frozen coverage contract executable:

```text
Walk once, LocalStop, no restart
  ⇒  Output = ArgMin(Accepted)
  ⇏  ArgMin_F

Walk then Restart until Unused = ∅
  ⇒  Accepted = X
  ⇒  Complete
  ⇒  Output = ArgMin_F
```

v0.4.5–v0.4.9, Cost, HB, and `R` remain frozen. Merged as
`727f0a3` (`#34`). Pareto-aware `Nxt` is
[`search-pareto-nxt.md`](search-pareto-nxt.md) (v0.4.11). No
`--s2c2-search`, no beam / rewrite, no
`P ↦ P'`, no shared `Acc` helper (still inline; later inhabitant).

```text
--s2c2-walk                 // restart=true (v0.4.9 default)
--s2c2-walk=restart=false   // one segment; LocalStop output
```

`restart=false` is a **witness switch**, not a second algorithm.
`N`, `S`, `Nxt`, and `Acc` are unchanged. Only `Rst` is withheld
after the first `Nxt = ⊥`.

On `@r4_same_program` / `F_0` the first Hamming-1 component is
the four `cpu-seq` members. After that LocalStop:

```text
ArgMin(Accepted) = {cpu-seq/*/cim}     total = 129
ArgMin_F         = {gpu-async, npu-*}  total = 128
```

so

```text
LocalStop  ⇏  ArgMin_F
```

is a measured fact, not only a design sentence. Default
`restart=true` still covers `X` (`Complete`, accepted=8) and then
`ArgMin(Accepted) = ArgMin_F` (W2/W3, unchanged).
