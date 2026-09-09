# Capacity-aware Residency (Phase 6C-D, query surface)

**Status:** 6C-B diagnostics FROZEN; 6C-C `CapacityPlan`
FROZEN (`selected=none`); 6C-D opens the consumer query
API. 5A–6B is the **stable
baseline** ([`stable-baseline.md`](stable-baseline.md)).
Phase 6C design
([PR #107](https://github.com/chenxingqiang/S2C2IR/pull/107))
froze \(F_{\mathrm{capacity}}\). 6C-B
([PR #108](https://github.com/chenxingqiang/S2C2IR/pull/108))
wired diagnostics and is frozen. 6C-C
([PR #109](https://github.com/chenxingqiang/S2C2IR/pull/109))
materialized the compiler-visible candidate object.
This cut does **not** rewrite, does **not** rank, does
**not** open `measured-capacity-v1`, does **not** change
`#69`, `cost-v04`, `default-3g`, or Evidence DB identity.
5E stays closed. Do not expand the 6C-B diagnostic surface.

```text
Goal     compiler-visible CapacityPlan is queryable without scheduling
Not      an eviction rewrite, a new Capability grid, or a device campaign
Rewrite  still only from an existing capability license
```

```text
Legality              ≠  Selection  ≠  Cost
F_capacity            ≠  F(program)          (4C product)
6C KEEP               ≠  3G KEEP_RESIDENCY
capacity exceeded     ≠  must evict (this object)
EVICT                 ≠  a semantic rewrite
TRANSFER              ≠  a new 6C action (existing realization)
measured-capacity-v1  ≠  this cut
```

## Why this cut

The baseline already answers movement and measured ranking.
The remaining Storage question is occupancy:

> When HBM / fast memory is finite, which residencies stay,
> which are dropped, and how is an evicted object restored?

6C does **not** start from a new KEEP/TRANSFER local rule.
It builds a new candidate family on live occupancy, then
reuses Evidence DB later.

```text
Semantic
   ↓
Residency / lifetime
   ↓
Capacity feasibility
   ↓
F_capacity
   ↓
CapacityPlan (selected=none)   ← 6C-C frozen
   ↓
query / consumer API           ← this cut
   ↓
Policy                         ← not this cut
Rewrite License                ← not this cut
Rewrite / HB                   ← not this cut
```

This cut stops at the diagnostic report:

```bash
s2c2-opt workload.mlir --capacity=hbm:2
s2c2-opt workload.mlir --capacity-spec=docs/design/v3-dataset/storage-capacity-4tile.jsonl
```

```text
capacity
peak occupancy
capacity conflict
F_capacity size
legal candidates
rewrite=no
```

`all-KEEP` of \(R_{t^\*}\) is **not** in \(F_{\mathrm{capacity}}\)
when occupancy exceeds \(C\). That is a candidate-space
constraint, not a greedy eviction rule.

## Occupancy

Each residency \(r\):

```text
id
object
space
size
live interval [t_start, t_end)
producer
consumer
reuse_distance
```

At program point \(t\):

$$
Live(R,t)=\sum_{r\in R_t} size(r)
$$

where \(R_t=\{r\mid t_{\mathrm{start}}(r)\le t < t_{\mathrm{end}}(r)\}\).

A **capacity conflict** exists iff \(\exists t.\; Live(R,t) > C\).
The first such \(t^\*\) is the conflict point. This cut
enumerates \(F_{\mathrm{capacity}}\) at \(t^\*\) only.

```text
Live ≤ C     →  F = { all KEEP }     enumerated=yes
Live > C     →  drop occupancy until Live ≤ C
```

Capacity exceeded means the **all-KEEP** assignment of
\(R_{t^\*}\) is **not** in \(F_{\mathrm{capacity}}\). It does
**not** pick which object to drop, and it does **not**
authorize rewrite.

From IR, constrained-space `stor.materialize` /
`stor.transfer` live ranges are
\([\mathrm{defOrder},\;\mathrm{lastUseOrder}+1)\),
each with default `size=1`. That is **tile-count occupancy
diagnostics** under `--capacity=hbm:2`, not a byte-capacity
allocator and not residency/alias analysis.
`discoverCapacityFromIR()` must not be treated as complete
lifetime analysis before an eviction rewrite.

`--capacity-spec` is a `s2c2.capacity.v1` JSONL occupancy
spec and overrides IR discovery. Extra keys are rejected.
`--capacity` may still override tiles and space from the
spec.

`reportCapacity()` runs on the **input** IR, before
`applySchedule()`. Occupancy is not computed on rewritten
IR. KEEP/EVICT candidates are not a rewrite license.

## Actions (first version)

```text
KEEP            retain r in the constrained space
EVICT           drop r from the constrained space
REMATERIALIZE   restore an evicted object by recompute
```

`TRANSFER` stays the **existing** restore realization
(reload from a lower space). It is not redefined here.

```text
restore-legal = TRANSFER | REMATERIALIZE
restore       = unspecified on this cut
```

Restore does **not** multiply \(F_{\mathrm{capacity}}\)
in the diagnostic witness. Each occupancy candidate names
one EVICT (or all-KEEP when there is no conflict).

## First-cut enumeration

When a single eviction restores \(Live(t^\*)\le C\):

```text
S0   evict the incoming object (latest t_start in R_t*)
     = keep the already-live working set
S1…  evict each remaining live object, sorted by object id
```

If one eviction is not enough, this cut reports
`enumerated=no truncated=yes` and does **not** invent a
pair-eviction product. Witness:
[`v3-dataset/storage-capacity-3tile-tight.jsonl`](v3-dataset/storage-capacity-3tile-tight.jsonl).

```text
F_capacity cannot invent objects
illegal ids cannot expand F
selection is not performed
rewrite=no
```

## First acceptance workload

Four tiles, one constrained space (`hbm`), unit size:

```text
capacity = 2 × tile
peak live = 3 × tile
```

```text
tile0 live [0, 3)
tile1 live [1, 4)
tile2 live [2, 5)
tile3 live [3, 6)
```

At \(t^\*=2\): live \(\{0,1,2\}\), \(Live=3>2\).

```text
capacity-conflict=yes
candidate #0 keep=0,1 evict=2
candidate #1 keep=1,2 evict=0
candidate #2 keep=0,2 evict=1
```

This proves candidate generation. It does **not** pick a
winner. Tile 3 is not in \(R_{t^\*}\).

Host witness (not a device log, not the hardware ledger):
[`v3-dataset/storage-capacity-4tile.jsonl`](v3-dataset/storage-capacity-4tile.jsonl).

Compiler witness: `s2c2-opt --capacity=2` on the 4-tile
IR in [`test/Integration/storage-capacity.mlir`](../../test/Integration/storage-capacity.mlir).
Prefix `s2c2-storage-capacity`. Same three legal
candidates. `rewrite=no`.

## Later (6C-C frozen; rewrite not opened)

```text
F_capacity diagnostics          ← FROZEN (6C-B)
   ↓
compiler-visible CapacityPlan   ← FROZEN (6C-C)
   ↓
query / consumer API            ← this cut (6C-D)
   ↓
policy                          ← not this cut
   ↓
rewrite license                 ← not this cut
   ↓
eviction / rematerialize rewrite
```

6C-C materializes `CapacityPlan` / `CapacityCandidateSet`:

```text
CapacityPlan
  ├── capacity
  ├── peak_live
  ├── feasible
  ├── candidates[]
  │     ├── KEEP set
  │     ├── EVICT set
  │     └── REMATERIALIZE set
  └── selected = none
```

Identity is stable:

```text
keep{0,1}|evict{2}|rematerialize{}
```

```text
F_capacity ⊆ F_residency
selected = none
policy = none
rewrite-license = no
rewrite = no
```

`s2c2-opt --dump-capacity-plan=` writes
`s2c2.capacity_plan.v1` JSON. It does **not** rewrite
KEEP / EVICT / REMATERIALIZE. Evidence DB is unchanged.
`measured-capacity-v1` is not opened.

## Query surface (6C-D this cut)

`CapacityPlan` is now reachable without running the
schedule pass:

```bash
s2c2-opt workload.mlir --query-capacity-plan --capacity=2
s2c2-opt workload.mlir --query-capacity-plan --capacity-spec=docs/design/v3-dataset/storage-capacity-4tile.jsonl
```

```text
prefix           s2c2-capacity-plan-query
schema           s2c2.capacity_plan.v1
selected         none
policy           none
rewrite-license  no
rewrite          no
```

`--query-capacity-plan` injects `--s2c2-capacity-plan-query`,
not `--s2c2-evidence-bounded-schedule`. It does **not**
print frozen 6C-B `s2c2-storage-capacity` diagnostics, load
Evidence DB, or call `applySchedule`. `--capacity` alone
still injects the schedule pass (6C-B/C unchanged).

Optional `--dump-capacity-plan=` writes the same JSON file
as 6C-C. Combining `--query-capacity-plan` with
`--schedule-policy` runs both passes; the query pass does
not rewrite, so the scheduler still sees input IR.

This is **not** `measured-capacity-v1`. Policy ranking and
eviction rewrite stay closed.

## Out of scope

```text
eviction rewrite / HB A/B
measured-capacity-v1
new Capability matrix
new hardware campaign
changing cost-v04 / default-3g / #69
changing Evidence DB identity
changing F(program) 4C product
C||Storage flatten
invented sibling sched.wait
FileCheck of microseconds
```
