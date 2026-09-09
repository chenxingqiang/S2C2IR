# Measured Storage, |F| > 2 (Phase 5B)

**Status:** FROZEN (PR #98). Design approved on PR #97. Phase
5A is **FROZEN** ([`storage-measured.md`](storage-measured.md)).
5B reused existing `F(@ssd_hierarchy_lifetime)` (product=8)
and recorded all eight candidate-local arms. On both 4090
and 910B, ArgMin is default-3g S0 (`diverge=no`). That is a
valid 5B result. Do **not** re-measure this 8-set. Next cut:
[`storage-measured-5c.md`](storage-measured-5c.md).

```text
Goal     natural |F(program)| > 2 with ≥ 3 measurable inhabitants
Not      manufacture diverge=yes on the frozen S0/S1 pair
Not      rank a truncated product
Rewrite  only after a real S_measured ≠ S_default-3g
```

```text
Legality              ≠  Selection  ≠  Cost
cost-v04              ≠  measured-storage-v1     (frozen)
measured-storage-v1   ≠  default-3g
5A coincide           ≠  the two policies are the same object
|F| = 2 coincide      ≠  evidence cannot distinguish schedules
ranking               ≠  rewrite license
KEEP_RESIDENCY in F   ≠  a destructive rematerialize rewrite
```

## Why this cut

5A proved the table can rank. It did **not** prove that
measured evidence can change the historical choice, because
the only fully measured \(F\) has two inhabitants and both
devices pick the same one.

A synthetic `measured=yes` table already shows the compiler
can report `diverge=yes`. That is a schema witness, not a
device fact. 5B asks for a **natural** set with more than two
legal Storage realizations, then measures them. Divergence is
allowed to be `no` again. Inventing a slower S0, or dropping
S0 from the table, is not 5B.

```text
S²C² can enumerate several legal Storage schedules
        ↓
candidate-local times on those inhabitants
        ↓
ArgMin may or may not equal default-3g
        ↓
only a real ≠  opens rewrite → HB → runtime A/B
```

## Existing enumerated F

Do **not** grow \(F\) with a new enumerator. These fixtures
already enumerate \(|F|>2\):

| Workload | product | Axes in F |
| -------- | ------- | --------- |
| `@ssd_hierarchy_lifetime` | 8 | PREFETCH/PRESERVE × two KEEP_RESIDENCY/TRANSFER sites |
| N-tile hierarchy | 4 | two independent PREFETCH/PRESERVE sites |
| `scf.for` loop hierarchy | 4 | PREFETCH/PRESERVE × KEEP_RESIDENCY/TRANSFER |
| `storage-aware-pipeline` | 2 | **frozen 5A pair — do not re-campaign** |
| `@seven_binary_chains` | 128 | truncated → `not-enumerated` |

Recommended first workload: `@ssd_hierarchy_lifetime`
(`test/Integration/storage-hierarchy.mlir`). 4090 / 910B
`default-3g` / `cost-v04` already coincide on this \(F\)
(`diverge=no`, product=8).

```text
S0  …//PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY     default-3g
S1  …//PREFETCH|TRANSFER|KEEP_RESIDENCY|TRANSFER
S2  …//PREFETCH|TRANSFER|TRANSFER|KEEP_RESIDENCY
S3  …//PREFETCH|TRANSFER|TRANSFER|TRANSFER
S4  …//PRESERVE|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
S5  …//PRESERVE|TRANSFER|KEEP_RESIDENCY|TRANSFER
S6  …//PRESERVE|TRANSFER|TRANSFER|KEEP_RESIDENCY
S7  …//PRESERVE|TRANSFER|TRANSFER|TRANSFER
```

This is the shape 5B needs:

```text
PREFETCH A | TRANSFER | KEEP
PRESERVE A | TRANSFER | KEEP
PREFETCH A | KEEP     | TRANSFER
…
```

N-tile / loop stay fallbacks if a honest hierarchy runtime
cannot realize the residency axis. They still beat `|F|=2`.

## What is missing

The compiler already names these signatures. 5A's runtime
only realizes **two** pipeline arms (`evi`→S0, `seq`→S1).
Hierarchy's timed witness is still that same two-arm log.
5B is a **per-signature runtime**, not more `F(site)` code.

```text
joinGlobal(S)  →  one runnable arm
measured=yes && correctness=1
profile-scoped
par-like extras stay out of F
```

`KEEP_RESIDENCY` versus `TRANSFER` on a later site is two
legal realizations of the same object run. Measuring both
does **not** authorize a rematerialize rewrite and does
**not** flatten `C||Storage`.

## Policy (unchanged)

```text
policy = measured-storage-v1          ← same 5A object
ranked ∈ {S ∈ F | measured=yes ∧ correctness=1}
         when that set has size ≥ 2
default-3g selected = historical tuple
cost-v04 = FROZEN
rewrite of the measured winner = not this design
```

## Freeze

```text
4090  ArgMin S0 = default-3g S0 → diverge=no
910B  ArgMin S0 = default-3g S0 → diverge=no
measured-count   8 / 8 legal signatures
one row          per (profile, workload, signature)
#69              unchanged
cost-v04         frozen
default-3g       unchanged
rewrite license  unchanged
```

`diverge=no` is the honest device fact. Do not drop S0 or
re-time a subset to manufacture `diverge=yes`. Do not
re-measure this 8-set. Next structural question:
[`storage-measured-5c.md`](storage-measured-5c.md). Rewrite
+ HB + runtime A/B stays gated on a later real `≠`.

Acceptance:

```text
1. |F(program)| > 2 and enumerated
2. ≥ 3 inhabitants have measured=yes && correctness=1
3. each measured row's signature inhabits F
4. ArgMin is whatever the device table says
5. diverge=yes  iff  ArgMin ≠ default-3g
   diverge=no   is an allowed honest result
6. #69 / cost-v04 / default-3g / 4B chain def unchanged
7. no FileCheck of microseconds
8. do not compare 4090 μs to 910B μs
9. 4090 rows are not 910B ranking evidence
```

Rewrite + HB + runtime A/B is a **later** cut, gated on a
real `diverge=yes` from this policy. A `diverge=no` 5B fill
still freezes as evidence. It does not authorize another
heuristic tick.

## Out of scope

```text
picking 3 of 8 signatures just to hit ≥ 3
re-measuring storage-aware-pipeline S0/S1
dropping S0 from a table to force diverge=yes
ranking @seven_binary_chains (truncated)
adding structural ticks to cost-v04
applying the measured winner as a rewrite
new Capability grid points
overwriting #69
C||Storage flatten
invented sibling sched.wait
changing the 4B chain definition
memory-capacity-aware residency (later)
```
