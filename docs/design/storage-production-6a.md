# Production Path (Phase 6A)

**Status:** FROZEN as part of the 5A–6B stable baseline
([`stable-baseline.md`](stable-baseline.md)).
Phases 5A–5D are **FROZEN**
([`storage-measured-campaign.md`](storage-measured-campaign.md)).
This cut turns the verified selection stack into a stable
`s2c2-opt` entry. It does **not** open 5E, does **not**
hunt for `diverge=yes`, does **not** retune 5A–5D, does
**not** change `cost-v04`, `#69`, `default-3g`, or rewrite
license.

```text
Goal     one compiler path: profile + policy + evidence + explain
Not      a new enumerator, a new F, or a rewrite of the winner
Rewrite  still only from an existing capability license
```

```text
Legality              ≠  Selection  ≠  Cost
Policy                ≠  legality
Policy                ≠  rewrite license
measured winner       ≠  license
5A–5D freeze          ≠  6A may retune those workloads
```

## Compiler path

```text
MLIR
  ↓
Profile
  ↓
Canonical evidence JSONL
  ↓
Legality  →  F(site) → F(chain) → F(program)
  ↓
Policy selection   default-3g | cost-v04 | measured-storage-v1
  ↓
Rewrite license    (unchanged; independent)
  ↓
Rewrite / preserve
  ↓
HB  (--check-s2c2-execution)
  ↓
Lowering (--s2c2-lower)
```

## Unified API

```bash
s2c2-opt workload.mlir \
  --profile=rtx4090 \
  --schedule-policy=measured-storage-v1 \
  --measured-cost-table=table.jsonl \
  --explain

s2c2-opt workload.mlir \
  --profile=910B \
  --schedule-policy=default-3g
```

`--schedule-policy` (or `--explain`) implies
`--s2c2-evidence-bounded-schedule`. Existing pass-local
syntax still works. Omitting the new flags keeps the
frozen 5A–5D diagnostic output unchanged.

```text
Policy
 ├── default-3g
 ├── cost-v04
 └── measured-storage-v1
```

Policy **selects** among already legal inhabitants. It
does not add members of \(F\), does not change
`default-3g` itself, and does not grant rewrite.

When the named policy cannot rank (truncated, wrong
profile, `measured=no`, fewer than two valid rows):

```text
applicable=no
selected = historical default-3g
rewrite  = no
```

## Canonical evidence

The compiler never reads campaign logs. It only consumes
JSONL records:

```text
profile
candidate_signature
measured
correctness
measured_time_us
```

`workload_class` and campaign notes are ignored for
matching. Match key remains `(profile, signature)` with
`measured=yes && correctness=1`. That is the 5A contract.

```text
benchmark logs  →  evidence builder (host)
                →  canonical JSONL
                →  s2c2-opt
```

Phase 6B stores those rows as `s2c2.evidence.v1` with
identity \(E=(profile, workload, candidate, revision)\)
and projects the ranking-eligible slice back to this
v1 table. See [`evidence-db.md`](evidence-db.md).
The compiler still does not read the Evidence DB,
campaign logs, or `hardware-ledger.jsonl`.

## Explain

`--explain` prints a stable, grep-able account of \(F\),
evidence, named-policy selection, and rewrite=no. Ranking
unit is **F(program)** (joinGlobal), not invented per-site
microseconds. Sites still report legal/selected under
`default-3g`. Do not FileCheck hardware microseconds.

## Invariants (negative matrix)

```text
unknown profile          → preserve concurrent
wrong profile table      → measured not-ranked
measured=no              → not-ranked
truncated                → not-ranked
illegal signature        → cannot expand F
historical tuple ∉ F     → fail
named policy             → rewrite=no
```

## Out of scope

```text
5E rewrite → HB → runtime A/B
re-measuring 5A / 5B / 5C / 5D
hunting for diverge=yes
changing cost-v04 ticks
retargeting default-3g
expanding #69
new Capability cells
capacity-aware residency (6C)
Evidence DB is 6B, not this cut
C||Storage flatten
invented sibling sched.wait
```
