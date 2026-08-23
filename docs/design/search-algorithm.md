# Algorithm object (v0.4.8)

Status: **v0.4.8 frozen**. Freezes the search *interface*
`A = (N, S, R, Nxt, Acc)`. Does not inhabit `A` with Hamming-1
hill-climbing, beam, multi-start, Pareto traversal, or rewrite
search, and does not add `--s2c2-search`. Neighbor v0.4.5, walk
verbs v0.4.6, and Start/Restart v0.4.7 remain frozen. Baseline:
`e564293` (`#31`).

```text
v0.4.5  X / Neighbor / LegalNeighbor           FROZEN
v0.4.6  Generate → Validate → [Score] → Select → Accept
                                               FROZEN in search-algorithm-contract.md
v0.4.7  StartPolicy / RestartPolicy            FROZEN in search-start-policy.md
v0.4.8  Algorithm = (N, S, R, Nxt, Acc)        this document
v0.4.9  Hamming-1 walk                         in search-walk-n1.md
v0.4.10 Restart / Complete                     later
v0.4.11 Pareto-aware search                    later
v0.4.12 Search verification                    later
v0.5    Realization transformation             later
```

```text
A            = (N, S, R, Nxt, Acc)
Nxt(State)   ∈ LegalNeighbor(current) ∪ {⊥}
Acc          : State × M → State'
next ≠ ⊥     ⇒  next ∈ LegalNeighbor(current)
current      changes only through Install or Acc
hill-climbing / beam / rewrite  ∉ this layer
π            ∉ A
```

---

## 1. Why this layer exists

v0.4.5–v0.4.7 name the pieces a walk *uses*. They do not package
them as one object with a total `Next` and a state-to-state
`Accept`. Later walks (Hamming-1, beam, Pareto, …) must be
different *inhabitants* of the same `A`, not new copies of `X`,
`R`, or Cost.

`--s2c2-argmin` remains batch `N_all` / Complete. It is not an
inhabitant of `A` (no path, no `Nxt`).

---

## 2. The object

```text
A = (N, S, Rst, Nxt, Acc)
```

| Slot | Already frozen | This layer |
| ---- | -------------- | ---------- |
| `N` | `Neighbor_F : F → 𝒫(F)` (v0.4.5) | used as-is |
| `S` | `StartPolicy(P, D; F) ∈ X` (v0.4.7) | used as-is |
| `Rst` | `RestartPolicy(Unused) ∈ Unused` (v0.4.7) | used as-is |
| `Nxt` | sketched as `first(Best)` (v0.4.6) | **interface** `State → LegalNeighbor ∪ {⊥}` |
| `Acc` | sketched as `Accepted ∪ {next}` (v0.4.6) | **interface** `State × M → State'` |

`Rst` is written `R` in informal text when it cannot be confused
with realization space `R(P, D)`. In the tuple the slot is `Rst`.

`Nxt` / `Acc` are functions, not “hill-climbing” or “beam”.
v0.4.9+ chooses a particular `N` and a particular `Nxt`.

---

## 3. State (unchanged carrier)

`Nxt` and `Acc` read the v0.4.6 walk state:

```text
State =
  ( current        ∈ X
  , Generated      ⊆ F
  , Checked        ⊆ F
  , LegalChecked   ⊆ X
  , Scored         ⊆ X
  , Accepted       ⊆ X
  , Cache          : device → Score_3 )
```

Invariants, required after every `Install` and every `Acc`:

```text
current        ∈ X
Accepted       ⊆ X
Checked        ⊆ F
Scored         ⊆ X
Accepted       ⊆ Scored ⊆ LegalChecked ⊆ X
Checked        ⊆ Generated ⊆ F
LegalChecked   = Checked ∩ X
```

`π` is not a field of `State`.

---

## 4. Next

```text
Nxt : State → LegalNeighbor_F(current) ∪ {⊥}
```

where, after `Neighbor(current)` has been Generated and Checked
(v0.4.6),

```text
LegalNeighbor_F(current) = Neighbor_F(current) ∩ LegalChecked
Frontier(current)        = LegalNeighbor_F(current) \ Accepted
```

```text
Nxt(State) = ⊥          iff  Frontier(current) = ∅
Nxt(State) ≠ ⊥          ⇒   Nxt(State) ∈ Frontier(current)
                        ⇒   Nxt(State) ∈ LegalNeighbor_F(current)
                        ⇒   Nxt(State) ∈ X
                        ⇒   Nxt(State) ∉ Accepted
```

`⊥` is **LocalStop** of this walk segment. It is not Complete
unless `Accepted ⊇ X` (v0.4.6 / v0.4.7). `Nxt` does not restart;
`Rst` does.

`Nxt` may read `Frontier`, `Scored`, and `Cache`. It must score
every `M ∈ Frontier` before choosing (v0.4.6: Validate → Score →
Select → Accept). It must not score `Checked \ X`.

This layer does **not** freeze `Nxt = first(Best)`. That is one
later inhabitant (scalar greedy). Other inhabitants (Pareto
policy, beam-of-k) are still `Nxt` functions of the same type.

---

## 5. Accept

```text
Acc : State × X → State'
```

A **step** accept is defined only when

```text
M = Nxt(State)  ∧  M ≠ ⊥
```

Then:

```text
current'     = M
Accepted'    = Accepted ∪ {M}
Generated'   = Generated
Checked'     = Checked
LegalChecked'= LegalChecked
Scored'      = Scored          // M ∈ Scored already (Frontier ranked)
Cache'       = Cache
```

```text
M ≠ ⊥  ⇒  M ∈ LegalNeighbor_F(current)
       ⇒  M ∈ X
       ⇒  M ∉ Accepted
Accepted' = Accepted ∪ {M}
current'  = M
```

There is no other write to `current` on a step. Start and restart
still use frozen `Install` (v0.4.7), which is *not* `Acc`:

```text
Install(M)     requires M ∈ X                 (not necessarily a neighbor)
Acc(State, M)  requires M = Nxt(State) ≠ ⊥    (a legal unused neighbor)
```

`Install` may grow `Generated` / `Checked` / `LegalChecked` /
`Scored` / `Accepted`. `Acc` does not re-Validate and does not
re-Score.

If `Nxt(State) = ⊥`, `Acc` is not applied.

---

## 6. One segment

```text
current ← Install(S(…))                 // start, or Rst then Install
loop:
    Generate N(current); Validate into Checked
    Score Frontier
    m ← Nxt(State)
    if m = ⊥:  LocalStop this segment; break
    State ← Acc(State, m)
if Accepted ⊇ X:  Complete
else if Rst defined on Unused ≠ ∅:  next segment
else:  stay LocalStop; Output = ArgMin(Accepted)
```

This is the *shape* of every later inhabitant. It is not a pass
and not a choice of `N` or `Nxt`.

---

## 7. Out of scope

```text
--s2c2-search
inhabiting A with N_1 / StartFirst / first(Best)
beam / SA / ILP / Pareto Next
multi-start coverage experiments
P ↦ P' rewrite search
unique M*
π in State or in A
Cost / HB / R / Enum / ArgMin listing changes
```

---

## 8. Tests

Design claims only. No new pass.

| ID | Claim |
| -- | ----- |
| V1 | `A = (N, S, Rst, Nxt, Acc)`; no inhabitant in this PR |
| V2 | `Nxt(State) ∈ LegalNeighbor(current) ∪ {⊥}` |
| V3 | `Nxt = ⊥ ⇔ Frontier = ∅`; `Nxt ≠ ⊥ ⇒ Nxt ∉ Accepted` and `Nxt ∈ X` |
| V4 | `Acc` only when `M = Nxt ≠ ⊥`; `current' = M`, `Accepted' = Accepted ∪ {M}` |
| V5 | `Install ≠ Acc`; start/restart still only via `Install` |
| V6 | invariants of §3 hold after `Install` and after `Acc` |
| V7 | `Nxt = ⊥` is LocalStop of a segment, not Complete unless `Accepted ⊇ X` |
| V8 | no `--s2c2-search`; hill-climbing / beam not chosen |
