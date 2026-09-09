# Measured Storage, last existing enumerated F (Phase 5D)

**Status:** design. Phase 5A / 5B / 5C are **FROZEN**. This
cut picks the last remaining fully enumerated \(|F|>2\) that
has not had per-signature `measured-storage-v1`. Do **not**
open a 4090 / 910B campaign until this design is approved.
Do **not** grow \(F\), do **not** add a Capability cell, do
**not** add ticks to frozen `cost-v04`, do **not** retarget
`default-3g`, and do **not** rewrite.

```text
Goal     a natural F whose axes jointly claim prefetch
         and live residency at the same time
Not      a 5C n-tile variant (two PREFETCH bits)
Not      a 5B hierarchy rematerialize 8-set
Not      a new enumerator invented to manufacture diverge
Rewrite  only in a later 5E, gated on a real diverge=yes
```

```text
Legality              ≠  Selection  ≠  Cost
cost-v04              ≠  measured-storage-v1     (frozen)
measured-storage-v1   ≠  default-3g
5A/5B/5C diverge=no   ≠  the two policies are the same object
ranking               ≠  rewrite license
loop-invariant KEEP   ≠  hierarchy rematerialize KEEP
prefetch || KEEP live ≠  two sequential PREFETCH sites
```

## Why this cut

5A, 5B, and 5C all measured a complete enumerated \(F\)
and froze as:

```text
4090  ArgMin = default-3g  →  diverge=no
910B  ArgMin = default-3g  →  diverge=no
```

```text
5A   |F|=2   one PREFETCH/PRESERVE
5B   |F|=8   PREFETCH/PRESERVE × two KEEP/TRANSFER
             rematerialize after compute
5C   |F|=4   two independent PREFETCH/PRESERVE
             KEEP frozen out of F
```

Those results proved measured ranking. They did **not**
prove that measured cost can change the historical choice.
The remaining untested question on **existing** fixtures is
the joint occupancy that 5B and 5C each held only one side
of:

```text
compute(i) || prefetch(i+1)
        +
keep prologue tile 0 resident across the loop
```

`default-3g` and `cost-v04` still pick both PREFETCH and
KEEP. A device may prefer **PRESERVE+KEEP** if holding the
prologue replica while the copy path is also prefetching
the next tile is worse than dropping the overlap. That is
a real chance of

```text
S_measured ≠ S_default-3g
```

without dropping S0 or inventing inhabitants. `diverge=no`
is still a fully valid 5D result. Do **not** pre-claim the
joint trade-off. The device table decides ArgMin.

## Existing enumerated F (do not grow)

| Workload | product | Axes in F | Status |
| -------- | ------- | --------- | ------ |
| `@ssd_pipeline_two_tiles` | 2 | one PREFETCH/PRESERVE | **5A FROZEN** |
| `@ssd_hierarchy_lifetime` | 8 | PREFETCH/PRESERVE × two KEEP/TRANSFER | **5B FROZEN** |
| `@ssd_ntile_pipeline` | 4 | two independent PREFETCH/PRESERVE | **5C FROZEN** |
| `@ssd_loop_pipeline` | 4 | **PREFETCH/PRESERVE × loop-invariant KEEP/TRANSFER** | **5D first target** |
| `@interleave_objects` | 1 | none | skip |
| `@seven_binary_chains` | 128 | truncated | `not-enumerated` |

Recommended first (and only remaining) workload:
`@ssd_loop_pipeline` (`test/Integration/storage-loop.mlir`).
Already enumerated (`chains=8`, `product=4`,
`truncated=no`). 4090 / 910B `default-3g` / `cost-v04`
already coincide on this \(F\) (`diverge=no`).

This is the last existing fully enumerated \(|F|>2\). There
is no later “try another fixture” on the current Storage
IR. If 5D is again `diverge=no`, freeze the evidence. Do
**not** retune tile size, \(k\), or trip count to
manufacture divergence. Do **not** invent a fifth schedule.

## Why this is not 5B and not 5C

5B KEEP is a rematerialize temptation **after** compute on
the hierarchy lifetime. PREFETCH and KEEP were sequential
choices on that object run. Both devices preferred KEEP
and PREFETCH independently, so the product winner was
still S0.

5C KEEP is **not in \(F\)**. The last n-tile chain is
`TRANSFER|TRANSFER` on every arm. 5C asked whether two
overlap sites contend. Dual PREFETCH still won.

5D KEEP is the **loop-invariant prologue replica** of tile
0. It stays live across `scf.for` **while** the body
prefetches tiles 1 and 2. The two axes are concurrent
resource claims:

```text
prefetch depth          compute(i) || SSD→Host(i+1)
residency reuse         skip tile-0 rematerialize
copy-engine occupancy   prefetch and/or rematerialize
compute overlap         same concurrent region
```

At least two inhabitants do different work, not a
permutation of the same copies:

```text
KEEP      skip the loop-invariant tile-0 copies
TRANSFER  actually perform those SSD→Host (and after-loop Host→HBM)
PREFETCH  overlap compute with next-tile host staging
PRESERVE  sequential compute, then host staging
```

Existing 3J `--storage-loop-wallclock` is **not** this
table. It times `T_evi` vs `T_seq` (PREFETCH vs PRESERVE)
with KEEP always on. That is two arms, not \(F\). Do **not**
overwrite `storage-loop-wallclock-4090.log` /
`storage-loop-wallclock.log`.

## Existing signatures (do not grow)

```text
PREFIX = MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//
S0 PREFIX+PREFETCH//TRANSFER//TRANSFER|KEEP_RESIDENCY|TRANSFER//MATERIALIZE   default-3g
S1 PREFIX+PREFETCH//TRANSFER//TRANSFER|TRANSFER|TRANSFER//MATERIALIZE
S2 PREFIX+PRESERVE//TRANSFER//TRANSFER|KEEP_RESIDENCY|TRANSFER//MATERIALIZE
S3 PREFIX+PRESERVE//TRANSFER//TRANSFER|TRANSFER|TRANSFER//MATERIALIZE
```

Four `MATERIALIZE` tokens are the compiler chain
signature, not an SSD-object count. Sites 0–2 are
per-object `MATERIALIZE`; the fourth is prologue tile 0
`MATERIALIZE|TRANSFER`. The trailing `MATERIALIZE` is
underdetermined tile-1 identity after `scf.if` and is the
same on every arm. Do **not** rewrite this prefix.

```text
cost-v04  S0=2  S1=3  S2=3  S3=4     coincide with default-3g
```

Those scores are what `s2c2-opt` prints. `PREFETCH=0`,
`PRESERVE=1`, rematerialize `TRANSFER=1` vs `KEEP=0`. Do
**not** renormalize. ArgMin is S0 either way.

```text
IR meaning
1. Eager tile0 SSD→Host→HBM
2. scf.for trip=2:
     compute(i) || prefetch(i+1)     or sequential
     Host→HBM(i+1)
     rematerialize temptation tile0  KEEP skips / TRANSFER copies
3. After loop: rematerialize tile0   bundled in the same KEEP chain
4. Tile1 via scf.if                  MATERIALIZE, same on all 4
```

Logical SSD remains a pageable host buffer, not NVMe.

## What a later implementation must do

The compiler already names these four signatures. 3J times
two arms. 5D is a **per-signature runtime** of the joint
prefetch × KEEP decision, not more `F(site)` code.

```text
joinGlobal(S)  →  one runnable arm
measured=yes && correctness=1
profile-scoped
measure all 4 legal signatures
same profile + workload + signature → one campaign row
```

Do **not** pick 3 of 4 just to hit ≥ 3. Do **not** let
runtime invent a fifth schedule and back-fill it into \(F\).
Do **not** map 3J `T_evi/T_seq` onto four signatures.

```text
measurement cannot expand F
```

A PRESERVE+KEEP winner is still two legal realizations of
the same object run. Measuring it does **not** authorize a
rewrite and does **not** flatten `C||Storage`.

## Policy (unchanged)

```text
policy = measured-storage-v1          ← same 5A/5B/5C object
ranked ∈ {S ∈ F | measured=yes ∧ correctness=1}
         when that set has size ≥ 2
default-3g selected = historical tuple
cost-v04 = FROZEN
rewrite of the measured winner = not this design
```

Acceptance when implementation is later approved:

```text
1. |F(program)| > 2 and enumerated; axes ≠ frozen 5B/5C products
2. all legal inhabitants measured (here: 4/4), each in F
3. measured=yes && correctness=1
4. ArgMin is whatever the device table says
5. diverge=yes  iff  ArgMin ≠ default-3g
   diverge=no   is an allowed honest result
6. #69 / cost-v04 / default-3g / 4B chain def unchanged
7. no FileCheck of microseconds
8. do not compare 4090 μs to 910B μs
9. 4090 rows are not 910B ranking evidence
10. do not re-measure 5A S0/S1, 5B hierarchy 8-set, or 5C n-tile 4-set
11. do not overwrite 3J loop wall-clock logs
```

```text
5D   measure all F  →  ArgMin  →  diverge?
5E   only if diverge=yes: rewrite → HB → runtime A/B
```

A `diverge=no` 5D fill still freezes as evidence. It does
not authorize another heuristic tick and does not license
a new enumerator.

## Out of scope

```text
opening a 4090 / 910B campaign before this design is approved
re-measuring @ssd_ntile_pipeline
re-measuring @ssd_hierarchy_lifetime
re-measuring storage-aware-pipeline S0/S1
picking 3 of 4 signatures just to hit ≥ 3
dropping S0 from a table to force diverge=yes
retuning n / k / trip to manufacture diverge=yes
ranking @seven_binary_chains (truncated)
adding structural ticks to cost-v04
applying the measured winner as a rewrite
new Capability grid points
overwriting #69
C||Storage flatten
invented sibling sched.wait
changing the 4B chain definition
memory-capacity-aware residency (later)
growing F with a new enumerator
overwriting 3J loop wall-clock artifacts
```
