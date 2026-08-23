# Concurrent sibling reorder (v0.5.1)

Status: **v0.5.1 frozen**. First non-identity inhabitant of frozen
`T : P → P' ∪ {⊥}`. Search (v0.4.5–v0.4.12), Cost, HB axioms,
`R`, and Transformation v0.5.0 remain frozen. Merged as `e49d5fe`
(`#39`).

```text
T_reorder(P) = Permute_C(P)   // one adjacent sibling swap, or ⊥
Accept(T_reorder, P)
    ⇔  P' ≠ P  ∧  HB(P') = HB(P)
X' = Enum_F(P', D)            // rebuilt, never reused
```

```text
--s2c2-xform=kind=concurrent-reorder
```

This is **not** a rewrite framework, not `--s2c2-search`, and not
Concurrent → Pipeline.

---

## 1. Why this inhabitant

`T_id` proves the layer exists. `T_reorder` is the first case with

```text
P' ≠ P
```

while the executable gate is still

```text
HB(P') = HB(P)     // equality, computed, not by construction
```

Only lexical order of **direct** `sched.concurrent` sibling tasks
may change. Task bodies, waits, tokens, `stor` / `comp` / `comm`
ops, and StageOrder are not rewritten.

Concurrent siblings have **no** ConstructOrder HB
(`NoOrderingRequirement`). An HB-independent swap therefore can
keep the edge set identical. `π = Topo(G_HB; IRRank)` may still
change because IR rank is a scoring tie-break. Cost *numbers* may
move; the Cost *model* is not redefined.

---

## 2. Candidate, not arbitrary permutation

Not every sibling permutation is legal. If `B` waits on `A`:

```text
A →_SW B
```

swapping `B` before `A` is SSA-illegal and is not HB-independent.

v0.5.1 only tries the first adjacent pair `(A, B)` such that

```text
A ↛_HB B  ∧  B ↛_HB A
```

on the **subtrees** of the two `sched.task` ops (any op in `A`
reaching any op in `B`, or the reverse), and neither subtree uses
a value defined in the other. No candidate ⇒ `T = ⊥` (IR
unchanged).

The **acceptance gate** is still the rebuilt graphs:

```text
HB_before = HB_after
```

same `PO ∪ SW ∪ ConstructOrder` walk as CheckS2C2Execution.
Compared as an **edge set** (successor list order is not HB).
If the sets differ, the swap is undone and `T = ⊥`.

---

## 3. Diagnostics

Success:

```text
s2c2-xform func=NAME kind=concurrent-reorder
s2c2-xform func=NAME accepted=1
s2c2-xform func=NAME hb-eq=1
s2c2-xform func=NAME x-rebuilt count=N
```

Reject (`T = ⊥`):

```text
s2c2-xform func=NAME kind=concurrent-reorder
s2c2-xform func=NAME accepted=0
```

`kind=id` is unchanged. `X'` is counted with shared
`isLegalRealization` only when accepted.

---

## 4. Out of scope

```text
--s2c2-search
general rewrite framework
Concurrent → Pipeline
Pipeline stage reorder
add / remove wait
move token producer
move transfer / change stor space
fuse / unfuse compute
change device / Cost / HB axioms
Search calling Transform
arbitrary (non-adjacent, HB-dependent) permutation
IREE / StableHLO / MPI
```
