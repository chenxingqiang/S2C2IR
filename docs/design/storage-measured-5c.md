# Measured Storage, structurally different F (Phase 5C)

**Status:** FROZEN (device fill on this cut). Design approved
on PR #99. Phase 5A and Phase 5B are **FROZEN**. Both 4090
and 910B measured all 4 legal signatures. ArgMin is
default-3g S0 (`PREFETCH|PREFETCH`) on both profiles
(`diverge=no`). That is a valid 5C result. Do **not**
pre-claim copy-engine contention: the table did not show a
mixed-site winner. Do **not** retune the workload to
manufacture `diverge=yes`. 5C is **not** a new Capability
grid, not new ticks on frozen `cost-v04`, not a retarget of
`default-3g`, and not a rewrite license.

```text
Goal     natural |F|>2 whose axes are structurally different
         from the frozen hierarchy rematerialize product
Not      re-measure @ssd_hierarchy_lifetime 8/8
Not      re-measure frozen pipeline S0/S1
Not      rank a truncated product
Rewrite  only after a real S_measured ≠ S_default-3g
```

```text
Legality              ≠  Selection  ≠  Cost
cost-v04              ≠  measured-storage-v1     (frozen)
measured-storage-v1   ≠  default-3g
5A/5B diverge=no      ≠  the two policies are the same object
ranking               ≠  rewrite license
two independent PREFETCH sites  ≠  KEEP vs TRANSFER on one chain
```

## Why this cut

5A and 5B proved the table can rank a complete enumerated
\(F\). Both froze as:

```text
4090  ArgMin = default-3g  →  diverge=no
910B  ArgMin = default-3g  →  diverge=no
```

On hierarchy, default-3g already prefers PREFETCH and
KEEP_RESIDENCY, and those were also the fastest arms.
Repeating that 8-set (16×, 32×) adds no new question.
5B's missing piece was **candidate-local runtime**. After
5B, the missing piece is a **different structural question**.

```text
5B   PREFETCH/PRESERVE × KEEP/TRANSFER × KEEP/TRANSFER
     on one rematerialize-heavy chain
5C   two independent overlap decisions
     on a 3-tile unroll
```

`cost-v04` scores every PREFETCH as 0. It cannot express
copy-engine contention between two simultaneous overlaps.
`default-3g` prefers PREFETCH at every evidenced overlap
site. A device may prefer **one** PRESERVE so the other
PREFETCH stays useful. That is a real chance of

```text
S_measured ≠ S_default-3g
```

without dropping S0 or inventing inhabitants. `diverge=no`
is still a fully valid 5C result.

## Existing enumerated F (do not grow)

| Workload | product | Axes in F | Status |
| -------- | ------- | --------- | ------ |
| `@ssd_pipeline_two_tiles` | 2 | one PREFETCH/PRESERVE | **5A FROZEN** |
| `@ssd_hierarchy_lifetime` | 8 | PREFETCH/PRESERVE × two KEEP/TRANSFER | **5B FROZEN** |
| `@ssd_ntile_pipeline` | 4 | **two independent PREFETCH/PRESERVE** | **5C first target** |
| `@ssd_loop_pipeline` | 4 | PREFETCH/PRESERVE × one KEEP/TRANSFER | fallback |
| `@interleave_objects` | 1 | none | skip |
| `@seven_binary_chains` | 128 | truncated | `not-enumerated` |

Recommended first workload: `@ssd_ntile_pipeline`
(`test/Integration/storage-ntile.mlir`). Already enumerated
(`chains=7`, `product=4`, `truncated=no`). 4090 / 910B
`default-3g` / `cost-v04` already coincide on this \(F\)
(`diverge=no`).

```text
PREFIX = MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//
S0 PREFIX+PREFETCH|TRANSFER//PREFETCH|TRANSFER//TRANSFER|TRANSFER   default-3g
S1 PREFIX+PREFETCH|TRANSFER//PRESERVE|TRANSFER//TRANSFER|TRANSFER
S2 PREFIX+PRESERVE|TRANSFER//PREFETCH|TRANSFER//TRANSFER|TRANSFER
S3 PREFIX+PRESERVE|TRANSFER//PRESERVE|TRANSFER//TRANSFER|TRANSFER
```

These four `MATERIALIZE` tokens are the compiler's chain
signature (`s2c2-opt` `hierarchy-global-candidate`), not a
count of SSD objects. Sites 0–2 are per-object
`MATERIALIZE`; the fourth is obj0 `MATERIALIZE|TRANSFER`.
Do **not** rewrite the prefix to three `MATERIALIZE` tokens.

```text
cost-v04  S0=2  S1=3  S2=3  S3=4     coincide with default-3g
```

Those scores are what `s2c2-opt` prints under frozen
`cost-v04`. `PREFETCH=0`, `PRESERVE=1`. The shared +2 is
the last-chain rematerialize `TRANSFER|TRANSFER` (KEEP
exists at those sites but is not an \(F\) axis). Do **not**
renormalize to `0/1/1/2`. ArgMin is still S0 either way.

Fallback if a honest n-tile runtime cannot realize both
overlap sites independently: `@ssd_loop_pipeline`
(`test/Integration/storage-loop.mlir`), product=4,
PREFETCH/PRESERVE × KEEP/TRANSFER. That axis set is closer
to 5B (5B already showed KEEP beat TRANSFER on hierarchy),
so it is second, not first.

## Runtime (this cut)

The compiler already names these four signatures. This cut
adds one `joinGlobal` arm per inhabitant
(`--storage-ntile-measured`). Device tables land only from
a real 4090 / 910B campaign. 5C is a **per-signature
runtime** of two independent prefetch decisions, not more
`F(site)` code.

```text
joinGlobal(S)  →  one runnable arm
measured=yes && correctness=1
profile-scoped
measure all 4 legal signatures
same profile + workload + signature → one campaign row
```

Do **not** pick 3 of 4 just to hit ≥ 3. Do **not** let
runtime invent a fifth schedule and back-fill it into \(F\).

```text
measurement cannot expand F
```

A mixed PREFETCH/PRESERVE winner is still two legal
realizations of the same object run. Measuring it does
**not** authorize a rematerialize rewrite and does **not**
flatten `C||Storage`.

## Policy (unchanged)

```text
policy = measured-storage-v1          ← same 5A/5B object
ranked ∈ {S ∈ F | measured=yes ∧ correctness=1}
         when that set has size ≥ 2
default-3g selected = historical tuple
cost-v04 = FROZEN
rewrite of the measured winner = not this design
```

## Device result (honest)

```text
4090  4/4  ArgMin = S0 PREFETCH|PREFETCH  = default-3g  → diverge=no
910B  4/4  ArgMin = S0 PREFETCH|PREFETCH  = default-3g  → diverge=no
```

Dual PREFETCH was still fastest on both devices. Mixed
PREFETCH/PRESERVE did not win. That does **not** prove
copy-engine contention is absent on every workload; it
proves that **this** \(F\) did not change the historical
choice. Freeze the evidence. Do not retune the workload.

```text
#69              unchanged
cost-v04         frozen
default-3g       unchanged
F(program)       unchanged
rewrite license  unchanged
```

Acceptance:

```text
1. |F(program)| > 2 and enumerated; axes ≠ frozen 5B product
2. all legal inhabitants measured (here: 4/4), each in F
3. measured=yes && correctness=1
4. ArgMin is whatever the device table says
5. diverge=yes  iff  ArgMin ≠ default-3g
   diverge=no   is an allowed honest result
6. #69 / cost-v04 / default-3g / 4B chain def unchanged
7. no FileCheck of microseconds
8. do not compare 4090 μs to 910B μs
9. 4090 rows are not 910B ranking evidence
10. do not re-measure 5A S0/S1 or 5B hierarchy 8-set
```

Rewrite + HB + runtime A/B is a **later** cut, gated on a
real `diverge=yes` from this policy. A `diverge=no` 5C fill
still freezes as evidence. It does not authorize another
heuristic tick.

## Out of scope

```text
re-measuring @ssd_hierarchy_lifetime
re-measuring storage-aware-pipeline S0/S1
picking 3 of 4 signatures just to hit ≥ 3
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
growing F with a new enumerator
```

Next structural question (design only):
[`storage-measured-5d.md`](storage-measured-5d.md). Do not
re-measure this n-tile 4-set.
