# Search Verification (v0.4.12)

Status: **v0.4.12 design**. Verifies the frozen inhabitants of
`A`. Does **not** add a third `Nxt`, beam, `--s2c2-search`, or
`P ↦ P'`. Baseline: `6240f61` (`#35`).

```text
N        = N_1
S        = StartFirst
Rst      = StartUnused
Nxt_0    = first(Best)                 // v0.4.9
Nxt_P    = first(Pareto(Frontier))     // v0.4.11
```

`--s2c2-walk=verify` is a **witness switch**, like `restart=false`.
It asserts State invariants after every `Install` and `Acc` and
prints `verify` lines. Default `verify=false` leaves v0.4.9–v0.4.11
output unchanged.

IDs **S1–S8** below are this layer only (not v0.4.1 Search/Pareto
S1–S6). Test-plan labels are **SV1–SV8**.

---

## S1 — Nxt totality

```text
Nxt(State) ∈ Frontier ∪ {⊥}
Nxt = ⊥  ⇔  Frontier = ∅
```

A nonempty Frontier always has a successor (`first(Best)` or
`first(Pareto)`). `verify` fails the pass if this is violated.

## S2 — Determinism

Same `(P, F, nxt, restart)` ⇒ the same stderr trace. Two runs of
`--s2c2-walk=verify` must `diff` equal.

## S3 — Complete coverage

```text
restart=true  ∧  Nxt = ⊥  ∧  Unused = ∅
  ⇒  Accepted = X
  ⇒  Complete
  ⇒  ArgMin(Accepted) = ArgMin_F
  ⇒  Pareto(Accepted) = Pareto_F     // when nxt=pareto
```

On `@r4_same_program` / `F_0`: `complete accepted=8`,
`argmin count=4`.

## S4 — LocalStop ≠ ArgMin_F

```text
restart=false  ∧  Nxt = ⊥  ∧  Unused ≠ ∅
  ⇒  LocalStop
  ⇒  ArgMin(Accepted) ⇏ ArgMin_F
```

Same witness as v0.4.10: 129 ≠ 128.

## S5 — Restart ≠ Reset / coverage growth

After LocalStop, `Install(StartUnused)` keeps
`Generated` / `Checked` / `Scored` / `Cache` / `Accepted`.
Accepted only grows: `4 → 6 → 8` on `F_0`.

## S6 — State invariants

After every `Install` and every `Acc`:

```text
current            ∈ X
Accepted           ⊆ Scored ⊆ LegalChecked ⊆ X
Checked            ⊆ Generated ⊆ F
LegalChecked       = Checked ∩ X
π                  ∉ State
```

`verify` prints `ok=1` or fails the pass.

## S7 — Two Nxt inhabitants, not one

```text
Nxt_P ≠ Nxt_0     in general     // oracle (10,0,0) vs (0,0,6)
Nxt_P = Nxt_0     on @r4 / F_0   // contention-monotone Score_3
```

`verify` does not pick a third policy.

## S8 — Search is still selection

IR is unchanged (`sched.concurrent`, no `memref.copy`).
No `winner=`, no `pi=`, no `--s2c2-search`. Cost / HB / `R` /
Neighbor / Start / Restart are not revised.

---

## Out of scope

```text
--s2c2-search
beam / SA / ILP / a third Nxt
extracting Acc
P ↦ P'
Cost / HB / R changes
```
