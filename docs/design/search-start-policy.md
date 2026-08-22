# StartPolicy and RestartPolicy (v0.4.7)

Status: **v0.4.7 frozen**. Names how a walk *enters* `X` and how it
*re-enters* after `LocalStop`. Does not pick beam / hill-climbing /
first-of-`F_0` / global-best as *the* algorithm, and does not add
`--s2c2-search`. Search Algorithm Contract v0.4.6 remains frozen.
Baseline: `d1f16b7` (`#30`).

```text
v0.4.5  Search Space / Neighbor / Legality     FROZEN
v0.4.6  Search Algorithm Contract              FROZEN in search-algorithm-contract.md
v0.4.7  StartPolicy / RestartPolicy            this document
v0.4.8+ algorithm pass / rewrite generators    later
```

```text
StartPolicy    : → current_0 ∈ X
RestartPolicy  : Unused → current ∈ Unused
Install(M)     : Generate / Validate / [Score] / Accept on a start
StartPolicy    ⇏ ArgMin_F
first(F_0)     ≠ the algorithm
global best    ≠ the algorithm
π              ∉ StartPolicy
```

---

## 1. Why this layer exists

v0.4.6 freezes the walk once `current ∈ X` is known:

```text
Generate → Validate → [Score] → Select → Accept
```

It only requires

```text
current_0 ∈ X
```

and leaves the choice open on purpose. Closing it now as
`first(F_0)` or `ArgMin_F` would pick an algorithm backwards.
This document names the **policy objects**, not a winner among
them.

`--s2c2-argmin` stays the `N_all` / `Complete` witness and does
not use `StartPolicy`. A later `N_1` walker is the first consumer.

---

## 2. StartPolicy

```text
StartPolicy(P, D; F) ∈ X(P, D; F)
```

`X` is already `Enum_F = R ∩ F`. The policy returns one feasible
realization. It does **not** return `π`, a rewrite of `P`, or a
member of `F \ X`.

### What StartPolicy may read

```text
P, D, F, X
F_0 declaration order
```

It may read `X` as a listed set (the enumerator already can). It
must not require `ArgMin_F` or `Pareto_F` as an input. Computing
the global scalar minimum in order to *start* would make a later
local walk redundant and would freeze “best-start” as the
algorithm.

### What StartPolicy must not read

```text
π
unlisted maps outside F
Cost tables other than shared Score_3 (and only after Install)
beam width / temperature / random seed
```

Random start is not a v0.4.7 policy. It is not deterministic and
is left to a later algorithm layer.

### Install

Whatever `StartPolicy` returns is installed with the v0.4.6 start
contract. There is no back door into `current`.

```text
Install(M)  for M ∈ X:
  current          ← M
  Generated        ← Generated ∪ {M}
  Checked          ← Checked ∪ {M}
  LegalChecked     ← LegalChecked ∪ {M}
  Score(M)                            // Cache[device], Scored
  Accepted         ← Accepted ∪ {M}
```

```text
StartPolicy → Install → current_0
```

`Install` is Generate / Validate / `[Score]` / Accept on a
singleton that is already known to be in `X`. Validate is still
recorded in `Checked` so later Neighbor hits do not re-run it.

---

## 3. Catalog (kinds, not a choice)

These are named kinds. This layer does **not** freeze one of them
as the compiler default.

| Kind | Definition | Notes |
| ---- | ---------- | ----- |
| `StartFirst` | first member of `X` in `F_0` product order | deterministic, cheap; a *witness*, not the algorithm |
| `StartUnused` | first member of `X \ Accepted` in `F_0` order | used by restart; empty iff `Accepted ⊇ X` |
| `StartGiven` | caller supplies `M ∈ X` | tests / harness; reject `M ∉ X` |
| `StartBest` | any member of `ArgMin_F` | **reserved**; not selected here; would compute the batch answer first |
| `StartRandom` | later | not deterministic |

`StartFirst` and `StartUnused` exist so a future walker can be
FileCheck-stable without this document claiming “search is
first-of-`F_0` hill-climbing”.

`StartBest` is recorded so it is not invented later as a silent
default. Using it as the only start of an `N_1` walk is allowed
only in a later algorithm PR that says so explicitly.

---

## 4. RestartPolicy

A single `N_1` walk need not cover `X` (v0.4.6: the legal subgraph
need not have a Hamiltonian path). Completeness uses restart.

```text
Unused = X \ Accepted
```

On `LocalStop`:

```text
if Unused = ∅:
    label Complete          // Accepted ⊇ X
else if no restart:
    label LocalStop
    Output = ArgMin(Accepted)     // not ArgMin_F
else:
    current ← RestartPolicy(Unused)
    Install(current)              // current already ∈ X; Install is idempotent on Checked
    resume Generate → …
```

```text
RestartPolicy(Unused) ∈ Unused ⊆ X
```

`StartUnused` is the deterministic *witness* kind for restart.
This document does not freeze beam-style multi-current restart.

`Install` on an already-`Accepted` member is not used: restart
picks from `Unused`, so the new current was not accepted.

After a restart, `Generated` / `Checked` / `Scored` from the
previous walk are **kept**. Do not forget illegal flips or device
scores. Only `current` changes (and `Accepted` grows by the new
start).

---

## 5. Completeness with restarts

```text
Walk then Restart until Unused = ∅
  ⇒  Accepted ⊇ X
  ⇒  Complete
  ⇒  Output = ArgMin_F / Pareto_F
```

```text
Walk once, LocalStop, no restart
  ⇒  Output = ArgMin(Accepted)
  ⇏  ArgMin_F
```

Restart is how `N_1` may become Complete without claiming one
greedy path visits every member of `X`.

`--s2c2-argmin` remains Complete without `StartPolicy` or
`RestartPolicy` (`N_all`, `State = X`).

---

## 6. Algorithm tuple (still uninhabited)

A later algorithm is a tuple of already-named objects:

```text
Algo = ( Neighbor
       , StartPolicy
       , RestartPolicy
       , Next = first(Best)     // frozen v0.4.6 WalkTieBreak
       )
```

v0.4.7 fills the two holes `StartPolicy` and `RestartPolicy` as
*types*. It does not inhabit `Algo` with beam, hill-climbing,
Pareto traversal, or IR-rewrite search.

---

## 7. Out of scope

```text
--s2c2-search
freezing StartFirst or StartBest as the compiler default
beam / SA / ILP
random start
π as a start coordinate
scoring M ∉ X
unique M*
Cost depending on sched / spaceMap
Token / Concurrent / Pipeline rewrite
residency placement
```

---

## 8. Tests

Design claims only. No new pass.

| ID | Claim |
| -- | ----- |
| U1 | `StartPolicy(P, D; F) ∈ X`; `π ∉` its input |
| U2 | `StartPolicy` must not require `ArgMin_F` as an input |
| U3 | `Install(M)` is the only way `current` is set; v0.4.6 start sets hold |
| U4 | `StartFirst` / `StartUnused` / `StartGiven` are named kinds, not *the* algorithm |
| U5 | `StartBest` is reserved; not the v0.4.7 default |
| U6 | `RestartPolicy(Unused) ∈ Unused`; keeps `Checked` / `Cache` |
| U7 | restarts until `Unused = ∅` ⇒ Complete; one LocalStop without restart ⇏ `ArgMin_F` |
| U8 | `--s2c2-argmin` still does not use `StartPolicy` |
