# Transformation Composition / Legality (v0.5.2)

Status: **v0.5.2 frozen**. Docs-only. Names how frozen `T` maps
compose. Does **not** add a kind, a compose pass, or
`--s2c2-search`. Search (v0.4.5–v0.4.12), Cost, HB axioms, `R`,
and Transformation v0.5.0–v0.5.1 remain frozen. Merged as
`27e832a` (`#41`).

```text
T : P → P' ∪ {⊥}

(T_b ∘ T_a)(P) =
    ⊥     if T_a(P) = ⊥
    ⊥     if T_a(P) = P_1  ∧  T_b(P_1) = ⊥
    P_2   if T_a(P) = P_1  ∧  T_b(P_1) = P_2
```

The composite is itself a `T`. Same gates:

```text
(T_b ∘ T_a)(P) ≠ ⊥  ⇒  HB(P_2) = HB(P)
(T_b ∘ T_a)(P) = ⊥  ⇒  P unchanged
X_i = Enum_F(P_i, D)     // rebuilt at every successful step
```

`T_id` and `T_reorder` stay the only inhabitants. This document
does not inhabit a third.

---

## 1. Why this is not a walk of programs

A later walk `P → P_1 → P_2 → ⋯` that *keeps* intermediates is
**Transformation Search**. It is out of scope.

Binary composition is one `T`:

```text
success  →  P_2 replaces P
failure  →  original P     // undo P_1 if T_b failed
```

`T_b = ⊥` after a successful `T_a` does **not** leave `P_1` in
place. Keeping `P_1` would be a two-step walk.

```text
Compose ≠ Walk
Compose ≠ Neighbor
Compose ≠ Nxt
Search does not apply T or T_b ∘ T_a
```

No `T₁ → T₂ → T₁ → ⋯` loop. `T_reorder ∘ T_reorder` may yield
`P` again; that is a fact about the inhabitant, not a license
to iterate.

---

## 2. Per-step legality (origin, not transitivity)

Write `P_0 := P`. After successful step `i ∈ {1,2}`:

```text
local   :  HB(P_i) = HB(P_{i-1})     // existing T gate
origin  :  HB(P_i) = HB(P_0)         // composition gate
X_i     =  Enum_F(P_i, D)            // K10; never reuse X_{i-1}
```

`local` is the frozen v0.5.0 contract on that step. `origin`
must be **re-proved** by building `HB(P_i)` and `HB(P_0)` and
comparing edge sets. Transitivity of equality is **not** an
accepted proof. A later step must not treat “the previous step
proved HB” as authorization.

```text
M ∈ R(P_i, D)  ⇔  IsLegal(P_i, D, M) ∧ HB_M = HB(P_i)
```

`IsLegal` is re-run on `P_i`. `HB_M = HB(P_i)` and, after a
successful step, `HB(P_i) = HB(P_0)`.

`π = Topo(G_HB; IRRank)` may differ on each `P_i`. Cost *model*
unchanged.

---

## 3. Failure and identity

```text
T(P) = ⊥           ⇒  P unchanged          // frozen
(T_b ∘ T_a)(P) = ⊥ ⇒  P_0 unchanged        // undo P_1 if needed
T_id ∘ T  =  T  =  T ∘ T_id                // T_id always succeeds
```

Only binary `∘` is defined. n-fold composition and associativity
as an implementation are later. Mathematically, if every step
succeeds and each origin gate holds, then
`(T_c ∘ T_b) ∘ T_a` and `T_c ∘ (T_b ∘ T_a)` agree on `P`.

No `--s2c2-xform=compose`. No driver that applies two kinds.

---

## 4. Witnesses (existing inhabitants only)

```text
T_id ∘ T_id           = T_id
T_id ∘ T_reorder      = T_reorder
T_reorder ∘ T_id      = T_reorder
T_reorder(wait_sib)   = ⊥     ⇒  any composite with that step is ⊥
```

These are paper witnesses. They are not a new pass.
Coincidence FileCheck (both succeed, or `T_a = ⊥`) is
[`realization-transform-compose-witness.md`](realization-transform-compose-witness.md)
(v0.5.3). That is not a compose implementation.

---

## 5. Out of scope

```text
--s2c2-search
kind ≠ {id, concurrent-reorder}
compose CLI / apply-two-kinds pass
keeping P_1 when T_b = ⊥
n-fold / Kleene T* / iterate until fixed point
arbitrary concurrent permutation
Concurrent → Pipeline
changing Cost / HB axioms / Neighbor / Nxt
Transformation Space / search over P
IREE / StableHLO / MPI
```
