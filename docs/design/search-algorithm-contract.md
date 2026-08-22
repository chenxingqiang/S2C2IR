# Search Algorithm Contract (v0.4.6)

Status: **v0.4.6 frozen**. Contract for walking frozen
`(X, Neighbor, LegalNeighbor)`. Does not add `--s2c2-search`, does
not pick beam / hill-climbing as *the* algorithm, and does not
rewrite `P`. Search Space v0.4.5, ArgMin listing v0.4.4, and Cost
v0.1–v0.3 remain frozen. Baseline: `3a33468` (`#29`).

```text
v0.4.4  listing `--s2c2-argmin`                FROZEN
v0.4.5  Search Space / Neighbor / Legality     FROZEN in search-space.md
v0.4.6  Search Algorithm Contract              this document
v0.4.7+ algorithm pass / rewrite generators    later
```

```text
Generate     : Neighbor_F(M) ⊆ F
Validate     : IsLegal ∧ HB_M = HB_source
[Score]      : only after Validate, only for M ∈ X
Select       : Best / next on already-scored Frontier
Accept       : LegalNeighbor ⊆ X
WalkTieBreak ≠ ArgMin collapse
Complete     ≠ LocalStop
π            ∉ State
```

Generate / Validate / Accept remain the three **semantic** actions.
The walk order is

```text
Generate → Validate → [Score] → Select → Accept
```

`[Score]` fires when a validated member of `X` must be ranked. It
is not gated on Accept. Do not use `emit` for both a candidate and
a final answer.

---

## 1. Why this layer exists

v0.4.5 already answers *what* may be generated, validated, and
accepted:

```text
X(P, D; F)              = Enum_F = R ∩ F
Neighbor_F(M)           ⊆ F
LegalNeighbor_F(P, D, M)= Neighbor_F(M) ∩ X
```

It does not answer how a walk is *run*. This document freezes the
run objects:

```text
State
Checked / LegalChecked / Scored / Accepted
Termination
Score cache
Tie preservation
Next-state policy
```

`--s2c2-argmin` remains batch optimization on `X` with implicit
`N_all`. It already satisfies this contract as the `N_all` /
complete case. A later local walker would be the first consumer of
`N_1`. Neither new pass is in this PR.

---

## 2. State

`X` is relative to a fixed `P`. State never stores `π`.

### Batch / `N_all`

```text
State_all = X
```

No path. The whole feasible set is the state.

### Local / `N_1` (and any `N` used as a walk)

```text
State_walk =
  ( current        ∈ X
  , Generated      ⊆ F
  , Checked        ⊆ F
  , LegalChecked   ⊆ X
  , Scored         ⊆ X
  , Accepted       ⊆ X
  , Cache          : device → Score_3 )
```

A path **starts** in `X`. The start is generated, validated, scored,
then accepted:

```text
current_0        ∈ X
Generated_0      ⊇ {current_0}
Checked_0        ⊇ {current_0}
LegalChecked_0   ⊇ {current_0}
Scored_0         ⊇ {current_0}
Accepted_0        = {current_0}
Cache[current_0.device] filled
```

`Neighbor` may still name illegal `M' ∈ F`. Those land in
`Generated`, fail Validate, stay in `Checked \ LegalChecked`, and
never enter `Scored` or `Accepted`.

`D` is the declared `Dev_F` axis, not a second filter.

```text
Scored ⇏ Accepted
Accepted ⊆ Scored
```

because every accepted state was scored first. A Frontier member
may be in `Scored` and not yet in `Accepted`.

---

## 3. Checked, LegalChecked, Scored, Accepted

Split named candidates from validated ones. `Generated` alone
cannot remember a failed Validate.

```text
Generate(M)     = Neighbor_F(M)
Generated       ← Generated ∪ Generate(M)

for M' ∈ Generate(M) \ Checked:
    Validate(M') = IsLegal(P, D, M') ∧ HB_{M'} = HB_source
                 ⇔ M' ∈ X
    Checked      ← Checked ∪ {M'}
    if M' ∈ X:
        LegalChecked ← LegalChecked ∪ {M'}
```

```text
Generated    ⊆ F
Checked      ⊆ Generated
LegalChecked = Checked ∩ X
```

Do not re-Validate a member of `Checked`. After every neighbor of
`M` has been checked,

```text
LegalNeighbor_F(M) = { M' ∈ Neighbor_F(M) | M' ∈ LegalChecked }
                   = Neighbor_F(M) ∩ LegalChecked
Frontier(M)        = LegalNeighbor_F(M) \ Accepted
```

This is the same set as `Neighbor_F(M) ∩ X \ Accepted`, with
Validate remembered in state instead of re-run.

```text
Accept(M')  ⇔  M' ∈ Frontier(current) after Select
Accepted    ⊆ LegalChecked ⊆ X
```

---

## 4. Score cache

Frozen v0.3:

```text
Score_3(P, M) = Score_3(P, M.device, HB(P), π(P))
```

```text
Cache : Dev_F → Score_3
```

`Cache` records scores of **validated legal** members of `X` that
have been evaluated, whether or not they are already accepted.

```text
Score(M) is defined only for M ∈ X
Fill Cache[device] the first time some M ∈ LegalChecked
     with that device is scored
Scored ← Scored ∪ {M}
M ∈ Scored  ⇒  M ∈ X
device ∈ dom(Cache)  ⇔  some M ∈ Scored has M.device = device
```

Frontier ranking scores every `M' ∈ Frontier` **before** Select /
Accept:

```text
Validate → Score → Select → Accept
```

Reuse `Cache[device]` for every later legal `M` with that device.
Do not grow a second device table. Do not score `Checked \ X`.

```text
same device ⇒ same Score_3 number
distinct sched / spaceMap at that device remain distinct members
```

---

## 5. Tie preservation

`ArgMin_F` is a **set**. This contract must not collapse it.

```text
WalkTieBreak ≠ ArgMin_F
WalkTieBreak ≠ Pareto_F
```

F_0 declaration order may pick **which already-scored Frontier
member a walk steps to**. It must not delete other minima from
the **output set**.

On frozen Score_3, same-device `sched` / `spaceMap` are score ties.
A walk may visit one of them first; the output set still keeps
every accepted member with the best total (and every Pareto
non-dominated member, if that output is requested).

No lexical IR rule, no extra HB, no `π` tie-break.

---

## 6. Next-state policy

Policy is a function on the frontier, not a Cost revision and not
a rewrite.

```text
Frontier(M) = (Neighbor_F(M) ∩ LegalChecked) \ Accepted
```

Every member of `Frontier(M)` is scored before `Best(M)` is read.

### Batch / `N_all`

No next state. Output is computed on `X` in one shot:

```text
Output_ArgMin  = ArgMin_F
Output_Pareto  = Pareto_F
Completeness   = Complete
```

`--s2c2-argmin` is this case.

### Local walk / `N_1`

If `Frontier(current) = ∅`, the walk does not step (§7).

Otherwise let

```text
Best(M) = { M' ∈ Frontier(M) |
            Score(M').total = min_{N ∈ Frontier(M)} Score(N).total }
```

`Best(M)` is a set (ties stay). The **walk** needs one successor:

```text
next(M) = first(Best(M)) in F_0 product order
          (sched, then map, then device)
```

That `first` is `WalkTieBreak` only. `next(M)` is already in
`Scored`. Then:

```text
current  ← next(M)
Accepted ← Accepted ∪ {next(M)}
```

The search **output** after the walk is still a set (§8). It is
not `{current}`.

A later beam / queue would replace the single `current` with a
set of currents. That is a different policy on the same
`Frontier`. This document does not choose beam.

---

## 7. Termination

Three labels. An implementation must print which one it hit.
It must not pretend LocalStop is global ArgMin.

```text
Complete     Accepted ⊇ X
             (every feasible realization was accepted)

LocalStop    Frontier(current) = ∅  ∧  Accepted ⊉ X
             (no unused legal neighbor of the current state)

BudgetStop   later; not this document
```

`Complete` with `N_all` is the enumerate-then-argmin path already
implemented.

`Complete` with `N_1` on a connected legal subgraph also yields
`Accepted = X` if the walk (or a restart over unused members of
`X`) covers `X`. This document does not require a single `N_1`
path to cover `X`. The legal `F_0` subgraph need not be a path
from every start.

`LocalStop` output is **not** `ArgMin_F`. It is ArgMin over the
accepted subset (§8). Same N8 shape: restricting the set can
change the minimizer.

---

## 8. Output

```text
Output_ArgMin(Accepted) = argmin_{M ∈ Accepted} Score_3(M).total
Output_Pareto(Accepted) = Pareto(Accepted)
```

```text
Complete    ⇒  Output_ArgMin = ArgMin_F
               Output_Pareto = Pareto_F
LocalStop   ⇒  Output_ArgMin = ArgMin(Accepted)
               Output_ArgMin = ArgMin_F  only if Accepted ⊇ ArgMin_F
```

Output is a set. No `winner=`, no `m*=`, no `pi=`.

---

## 9. What this layer does not add

```text
--s2c2-search
beam / SA / ILP as the chosen algorithm
unique M* on ties
scoring Generated \ X
second legality matrix
Cost depending on sched / spaceMap
π in State
undeclared F' grown during the walk
Token / Concurrent / Pipeline rewrite
residency placement
IREE / StableHLO / MPI / CUDA / NPU ISA
```

If `P ↦ P'`, stop. Rebuild `X(P', D; F)` under v0.4.5. This
contract does not walk across programs.

---

## 10. Tests

Design claims only. No new pass. `--s2c2-argmin` is the Complete /
`N_all` witness.

| ID | Claim |
| -- | ----- |
| T1 | `State_all = X`; `State_walk.current ∈ X`; `π ∉ State` |
| T2 | `Checked ⊆ F`, `LegalChecked ⊆ X`; do not re-Validate `Checked`; illegal flips never scored |
| T3 | Cache fills on validated `M ∈ X`, including Frontier before Accept; keys are `device` |
| T4 | `WalkTieBreak` (F_0 order) does not shrink `ArgMin_F` |
| T5 | `next` is `first(Best)` in F_0 order; `Best` stays a set |
| T6 | `Complete ⇒ Output = ArgMin_F / Pareto_F` (`--s2c2-argmin`) |
| T7 | `LocalStop ⇏ Output = ArgMin_F` |
| T8 | no `--s2c2-search`; walk order is Generate → Validate → [Score] → Select → Accept |
| T9 | `Scored ⇏ Accepted` and `Accepted ⊆ Scored` |
