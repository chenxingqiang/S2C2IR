# Hamming-1 walk inhabitant (v0.4.9)

Status: **v0.4.9 design**. First executable inhabitant of frozen
`A = (N, S, Rst, Nxt, Acc)`:

```text
N   = N_1
S   = StartFirst
Rst = StartUnused
Nxt = first(Best)          // scalar Score_3.total; F_0 WalkTieBreak
```

Does not add `--s2c2-search`, beam, Pareto Next, or `P ↦ P'`.
v0.4.5–v0.4.8, Cost, HB, and `R` remain frozen. Baseline:
`0ad2dd4` (`#32`).

```text
--s2c2-walk
--s2c2-walk=scheds=...,maps=...,devices=...
```

Empty flags use `F_0`. The pass restarts until `Accepted = X`
(`Complete`). Each segment `LocalStop` is printed when
`Nxt = ⊥` and `Unused ≠ ∅`. After Complete, printed `argmin` is
`ArgMin_F`. Output is a set. `π` is not printed. IR is not rewritten.

`Nxt` is a **total** function on legal State (explicit v0.4.9
invariant, requested when v0.4.8 froze):

```text
Nxt(State) ∈ Frontier(current) ∪ {⊥}
Nxt(State) = ⊥   ⇔  Frontier(current) = ∅
Nxt(State) ≠ ⊥   ⇒  Nxt(State) = first(Best) ∈ Frontier
```

`first(Best)` = min `Score_3.total` on Frontier; ties use `F_0`
product order (`WalkTieBreak`). No `error`, no `undefined`, no
candidate outside `X`. FileCheck `F0-NEXT` locks every decision
as `step` or `localstop`.
