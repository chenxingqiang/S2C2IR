# Capacity-aware Residency (Phase 6C-I, license predicate)

**Status:** 6C-B diagnostics FROZEN; 6C-C `CapacityPlan`
FROZEN (`selected=none` on the diagnostic path); 6C-D
query FROZEN; 6C-E `s0` selection FROZEN; 6C-F
`measured-capacity-v1` ranking FROZEN; 6C-G rewrite-license
gate FROZEN (`rewrite-license=no`); 6C-H TRANSFER restore
records FROZEN; 6C-I classifies the structured license
predicate (necessary vs sufficient, still
`rewrite-license=no`). 5A–6B is the **stable
baseline** ([`stable-baseline.md`](stable-baseline.md)).
Phase 6C design
([PR #107](https://github.com/chenxingqiang/S2C2IR/pull/107))
froze \(F_{\mathrm{capacity}}\). 6C-B
([PR #108](https://github.com/chenxingqiang/S2C2IR/pull/108))
wired diagnostics and is frozen. 6C-C
([PR #109](https://github.com/chenxingqiang/S2C2IR/pull/109))
materialized the compiler-visible candidate object.
This cut does **not** rewrite, does **not** issue
`rewrite-license=yes`, does **not** start a hardware
campaign, and does **not** change `#69`, `cost-v04`,
`default-3g`, or Evidence DB identity. 5E stays closed.
Do not expand the 6C-B diagnostic surface. Do not
FileCheck microseconds.

```text
Goal     freeze necessary vs sufficient for a capacity rewrite license; result still no
Not      an eviction rewrite, a yes-license, IR alias analysis, or a device campaign
Rewrite  still only from an existing capability license
```

```text
Legality              ≠  Selection  ≠  Cost
F_capacity            ≠  F(program)          (4C product)
6C KEEP               ≠  3G KEEP_RESIDENCY
capacity exceeded     ≠  must evict (this object)
EVICT                 ≠  a semantic rewrite
TRANSFER              ≠  a new 6C action (existing realization)
selected              ≠  rewrite license
measured-capacity-v1  ≠  rewrite license
s0                    ≠  rewrite license
capability license    ≠  capacity license
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
query / consumer API           ← 6C-D frozen
   ↓
policy / selection (s0)        ← 6C-E frozen
   ↓
measured-capacity-v1 ranking   ← 6C-F frozen
   ↓
rewrite license gate           ← 6C-G frozen (still no)
   ↓
EVICT → TRANSFER restore       ← 6C-H frozen (candidate semantics)
   ↓
license predicate              ← this cut (necessary ≠ sufficient; still no)
   ↓
eviction rewrite               ← not this cut
```

This cut's consumer surface:

```bash
s2c2-opt workload.mlir --query-capacity-plan --capacity=2 \
  --capacity-policy=s0
python3 runtime/record_capacity.py --print-capacity-predicate-contract
```

Frozen 6C-B diagnostics remain:

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

## Later (6C-C–H frozen; predicate this cut; rewrite not opened)

```text
F_capacity diagnostics          ← FROZEN (6C-B)
   ↓
compiler-visible CapacityPlan   ← FROZEN (6C-C)
   ↓
query / consumer API            ← FROZEN (6C-D)
   ↓
policy / selection (s0)         ← FROZEN (6C-E)
   ↓
measured-capacity-v1 ranking    ← FROZEN (6C-F)
   ↓
rewrite license gate            ← FROZEN (6C-G; still no)
   ↓
EVICT → TRANSFER restore        ← FROZEN (6C-H)
   ↓
license predicate               ← this cut (6C-I; still no)
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
The diagnostic path does not rank.

## Query surface (6C-D frozen)

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

This default query is **not** `measured-capacity-v1`.
Eviction rewrite stays closed.

## Selection consumer (6C-E frozen)

The query API is the formal consumer of `F_capacity`.
Named policy selects one enumerated candidate; it does
**not** issue a rewrite license and does **not** rewrite.

```bash
s2c2-opt workload.mlir --query-capacity-plan --capacity=2 --capacity-policy=s0
s2c2-opt workload.mlir --capacity-policy=s0 --capacity=2
```

```text
policy           none | s0
s0               first(F_capacity) = evict incoming at t*
selected         candidate identity  (or none)
rewrite-license  no
rewrite          no
```

```text
selection ∈ F_capacity
selection ≠ rewrite license
s0 ≠ must-evict-this-object
truncated plan cannot be selected
```

`--capacity-policy` injects the query pass (same as
`--query-capacity-plan`). 6C-B/C `--capacity` without a
policy still prints `selected=none`. Combining with
`--schedule-policy` runs both passes; the scheduler's
`CapacityPlan` dump stays `selected=none`.

`--capacity-policy=measured-capacity-v1` without
`--measured-capacity-table` fails. Ranking is 6C-F.

## Measured ranking (6C-F frozen)

Enumerated \(F_{\mathrm{capacity}}\) can now be ranked
under scoped measured records (profile + workload +
candidate). ArgMin is
**selection only**. It does **not** issue a rewrite
license and does **not** rewrite.

```bash
s2c2-opt workload.mlir --query-capacity-plan --capacity=2 \
  --profile=fixture \
  --capacity-policy=measured-capacity-v1 \
  --measured-capacity-table=docs/design/v3-dataset/storage-capacity-measured-4tile.jsonl
```

```text
schema           s2c2.measured_capacity_cost.v1
match            profile + workload_class + candidate_identity
need             ≥2 scoped records with measured=yes and correctness=1
ArgMin           M ∩ F_capacity  (F order; ties pick earliest)
coincide-s0      yes iff selected == first(F_capacity)
prefix           s2c2-capacity-measured
rewrite-license  no
rewrite          no
```

```text
F_capacity → scoped measured capacity cost → ArgMin
M = { r | r.profile=P ∧ r.workload=W ∧ r.candidate ∈ F_capacity
          ∧ r.measured=yes ∧ r.correctness=1 }
measurement cannot expand F
wrong profile / wrong workload → ignored
truncated || !enumerated → failure
one usable record → measured-needs-two-records
count(profile, workload, candidate) > 1 → duplicate-measured-identity
ties → earliest F_capacity order
```

`--measured-capacity-table` injects the query pass, not
the schedule pass. Extra identities not in
\(F_{\mathrm{capacity}}\) are ignored. Duplicate scoped
identity \((P,W,c)\) is rejected; last-write-wins is not
a ranking rule. Equal times pick the earliest inhabitant
of \(F_{\mathrm{capacity}}\), not JSONL order. Do **not**
FileCheck microseconds. The tables under
[`v3-dataset/`](v3-dataset/README.md) are fixtures, not a
device campaign and not a new Evidence DB.
`workload_class` on this v1 table is the occupancy witness
(e.g. `ssd-capacity-4tile` from `--capacity-spec` / IR),
not an Evidence DB schema field.

On the 4-tile / capacity=2 witness, the fixture table
selects `keep{0,1}|evict{2}|rematerialize{}`
(`coincide-s0=yes`). A synthetic table selects
`keep{1,2}|evict{0}|rematerialize{}` (`coincide-s0=no`),
so ranking is not an alias of `s0`. Combined with
`--schedule-policy`, query may select the measured winner
while the scheduler `CapacityPlan` dump stays
`selected=none`. Ranking does **not** issue a license.

## Capacity rewrite-license gate (6C-G, frozen)

A selected capacity winner is **not** a rewrite license.
This cut freezes the gate that a later eviction rewrite
must pass. The printed result is still `no`.

```text
selected ∈ F_capacity
    ≠
capacity rewrite license
    ≠
eviction rewrite
    ≠
capability rewrite_license (concurrent→serial)
```

```text
prefix           s2c2-capacity-license
schema           s2c2.capacity_license.v1
rewrite-license  no
restore-legal    TRANSFER | REMATERIALIZE
rewrite          no
```

Necessary, **not** sufficient, for a future yes:

```text
enumerated && !truncated && selected ∈ F_capacity
```

EVICT must close through restore:

```text
for every object in selected.EVICT:
    restore must be specified
    restore ∈ {TRANSFER, REMATERIALIZE}
restore unspecified  ⇒  rewrite-license = no
REMATERIALIZE = ∅ this stage
    ⇒  only TRANSFER can close EVICT later
```

Printed restore classification (from the selected identity):

```text
selected=none                         restore=n/a          evict-closed=n/a
keep{…}|evict{}|rematerialize{}       restore=unused       evict-closed=n/a
nonempty EVICT, rematerialize{}       restore=unspecified  evict-closed=no
```

On the 4-tile / capacity=2 witness,
`keep{0,1}|evict{2}|rematerialize{}` has EVICT={2} and
empty rematerialize, so restore is unspecified and the
gate stays `no`. All-KEEP
(`keep{0,1}|evict{}|rematerialize{}`) does not need
restore (`unused`); that is still not a license.
`s0` and `measured-capacity-v1` cannot issue a license.

The gate prints only on the query consumer. It does **not**
print on frozen 6C-B/C `--capacity` diagnostics, does **not**
add `--capacity-license=yes`, does **not** add
`--dump-capacity-license`, and does **not** call
`applySchedule()`. Capability `rewrite_license` remains a
different object (concurrent→serial).

## EVICT → TRANSFER restore (6C-H, frozen)

The 6C-G gate still classifies restore from the selected
identity string (`restore=unspecified` / `evict-closed=no`
on `s2c2-capacity-license`). That print is **frozen**.
This cut attaches a structured restore record to each
EVICT object on the candidate, so a later `license=yes`
will not parse identity text.

```text
CapacityCandidate
    EVICT object
        ↓
restore realization = TRANSFER
        ↓
restore dataflow / validity
        ↓
proof of closure
        ↓
only then discuss license=yes   ← not this cut
```

```text
prefix           s2c2-capacity-restore
schema           s2c2.capacity_restore.v1
kind             TRANSFER
rewrite-license  no
rewrite          no
```

TRANSFER is the existing slower-space restore realization,
not a new 6C action. A TRANSFER restore is **valid** iff
the occupancy spec names a restore source for that object
on `ssd` or `host`. Occupancy IR (`--capacity=2` without
a spec) has no restore sources. Optional spec field
`restore_sources` is **not** occupancy and **not** a new
\(F_{\mathrm{capacity}}\) member. Extra unknown keys are
still rejected. Object ids are normalized the same way as
residencies (`tile2` → `2`).

```text
selected=none                         closed=n/a
keep{…}|evict{}|rematerialize{}       restore=unused  closed=n/a
EVICT nonempty, no source             valid=no        closed=no
EVICT nonempty, every source valid    valid=yes       closed=yes
closed=yes                            ≠  rewrite-license=yes
```

On the default 4-tile witness,
`keep{0,1}|evict{2}|rematerialize{}` has a TRANSFER record
for object `2` with `valid=no` (`no-source-replica`) and
`closed=no`. Fixture
[`v3-dataset/storage-capacity-4tile-transfer-restore.jsonl`](v3-dataset/storage-capacity-4tile-transfer-restore.jsonl)
declares SSD sources for tiles 0, 1, and 2; \(F_{\mathrm{capacity}}\)
is unchanged and the selected winner is `closed=yes`, still
`rewrite-license=no`. The frozen 6C-G license line remains
`restore=unspecified`.

The restore prefix prints only on the query consumer. It
does **not** print on frozen 6C-B/C `--capacity`
diagnostics. This cut does **not** invent IR alias analysis,
does **not** add extra funcs to the 4-tile module, and does
**not** open eviction rewrite.

## License predicate (6C-I, this cut)

`closed=yes` is **necessary, not sufficient** for a future
capacity rewrite license. This cut freezes that split as a
query-only predicate. It does **not** replace the frozen
6C-G identity-string gate or the 6C-H restore records.
`CapacityPlan.rewriteLicense` stays `false`.

```text
prefix           s2c2-capacity-predicate
schema           s2c2.capacity_predicate.v1
sufficient       no
rewrite-license  no
rewrite          no
```

Necessary conjuncts for an **EVICT rewrite** license:

```text
selected ∈ F_capacity
enumerated && !truncated
capacity-proof     selected assignment is occupancy-feasible
evict-closed=yes   every EVICT has a valid TRANSFER restore record
restore-kind=TRANSFER
```

Still **not** sufficient (always `no` this stage):

```text
source-data          restore source contents are live and correct
restore-ordering     TRANSFER is sequenced relative to uses
dest-invalidation    fast-space copy is dropped without stale reads
rewrite-path         an IR rewrite exists and is applied
```

```text
selected=none                         necessary=no   sufficient=no
all-KEEP (no EVICT)                   necessary=n/a  sufficient=no
EVICT, closed=no                      necessary=no   sufficient=no
EVICT, closed=yes                     necessary=yes  sufficient=no
necessary=yes ∧ sufficient=no         ≠  rewrite-license=yes
```

Occupancy `capacity-proof` is membership in enumerated
\(F_{\mathrm{capacity}}\), not a byte allocator and not
alias analysis. Source declaration (`has-source-replica`)
is **not** data-validity, restore ordering, or destination
invalidation. Those remain open; this cut does **not**
claim them.

The predicate prints only on the query consumer. Diagnostic
`--capacity` does not print it. No `--capacity-license=yes`,
no `--dump-capacity-license`, no `applySchedule()`, no
`replace`/`erase` of IR.

## Out of scope

```text
eviction rewrite / HB A/B
opening rewrite-license=yes
rematerialize rewrite
new Capability matrix
new hardware campaign
changing cost-v04 / default-3g / #69
changing Evidence DB identity
changing F(program) 4C product
C||Storage flatten
invented sibling sched.wait
FileCheck of microseconds
```

## After 6C-I

Architecture health check (evaluator ≠ search engine;
still no rewrite):
[`architecture-healthcheck.md`](architecture-healthcheck.md).
Does **not** open \(F_{\mathrm{storage\_schedule}}\), a
frontend, or eviction rewrite. Sufficient proofs stay
one conjunct per cut.
