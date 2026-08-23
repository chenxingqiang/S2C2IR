# Composition coincidence witnesses (v0.5.3)

Status: **v0.5.3 design**. FileCheck witnesses of frozen v0.5.2
facts that **coincide** with `(T_b ∘ T_a)` on IR. Uses only
existing `--s2c2-xform=kind=id` and `kind=concurrent-reorder`.
Does **not** implement compose, rollback, or a third kind.
Baseline: `c27f2fd` (`#42`).

```text
Sequential two-pass  ≠  (T_b ∘ T_a)
```

A pipeline of two Apply steps keeps `P_1` if the second `T`
returns `⊥`. Frozen composition would restore `P_0`. So these
tests only lock cases where the two agree:

```text
T_a = ⊥                         ⇒  both leave P_0
T_a and T_b both succeed        ⇒  both yield P_2
```

The rollback case (`T_a` succeeds with `P_1 ≠ P_0` and
`T_b = ⊥`) has **no fixture** among `{T_id, T_reorder}` and
stays paper-only (XC3) until an executable compose PR.

No `--s2c2-xform=compose`. No iterate-until-fixed-point.

---

## 1. Locked coincidences

On `@r4_same_program` both steps succeed:

```text
(T_reorder ∘ T_reorder)(r4)  =  r4     // involution on this fixture
(T_id ∘ T_reorder)(r4)       =  T_reorder(r4)
(T_reorder ∘ T_id)(r4)       =  T_reorder(r4)
```

Each successful Apply still prints `hb-eq=1` and rebuilds
`X_i` (`x-rebuilt count=8`). That is the per-step v0.5.0 gate,
not an origin-gate implementation of composition.

On `@wait_sibling`:

```text
T_reorder(wait) = ⊥  ⇒  two reorders stay at P_0
```

`T_reorder ∘ T_reorder` may equal `T_id` here. That does **not**
license a loop.

---

## 2. How the tests invoke T

```text
--s2c2-xform=kind=concurrent-reorder --s2c2-xform=kind=concurrent-reorder
--s2c2-xform=kind=id --s2c2-xform=kind=concurrent-reorder
--s2c2-xform=kind=concurrent-reorder --s2c2-xform=kind=id
```

Two existing passes. Not a compose driver.

---

## 3. Out of scope

```text
--s2c2-xform=compose
executable rollback of P_1 ≠ P_0
origin-gate HB(P_i) vs HB(P_0) in a compose engine
n-fold / T* / Transformation Search
kind ≠ {id, concurrent-reorder}
Concurrent → Pipeline
changing Cost / HB axioms
```
