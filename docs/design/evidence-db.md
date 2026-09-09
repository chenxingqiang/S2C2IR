# Evidence DB / Contract (Phase 6B)

**Status:** implementation. Phase 6A is the production
`s2c2-opt` path. Phases 5A–5D are **FROZEN**. 5E is **not
opened**. This cut turns campaign JSONL into a versioned
Evidence Contract. It does **not** open capacity-aware
residency (that is **6C**).

```text
Goal     a compiler-facing Evidence DB with stable identity E
Not      a new F, a rewrite, or capacity-aware residency
Rewrite  still not granted by evidence
```

```text
Legality              ≠  Selection  ≠  Cost
Evidence              ≠  Capability Schema v1
Evidence              ≠  hardware-ledger index
measurement_status    ≠  ledger status=measured
campaign log          ≠  compiler input
6A --measured-cost-table  still the optimizer ingest
```

## Why this cut

6A made this path real:

```text
s2c2-opt → profile → measured-storage-v1 → F(program) → selection
```

The ranking table is still a campaign export. Swapping a
device run should not require changing the optimizer.
6B puts a versioned store **in front** of the v1 projection
that `s2c2-opt` already consumes.

```text
Measurement
    ↓
Normalizer
    ↓
Evidence Record
    ↓
Evidence DB
    ↓
Applicability Query / v1 export
    ↓
s2c2-opt --measured-cost-table
```

## Identity

$$
E = (profile,\ workload,\ candidate,\ measurement\_revision)
$$

```text
profile                 compiler profile (rtx4090 | 910B)
workload_signature      F(program) family, not a log path
candidate_signature     joinGlobal(S)
measurement_revision    campaign / fixture slice
```

A later campaign is a new revision of the same
`(profile, workload, candidate)`, not a compiler change.

## Record (`schema=s2c2.evidence.v1`)

```text
profile
workload_signature
candidate_signature
measurement_status      measured | inferred | fixture | pending | invalid
correctness
cost.measured_time_us
scope                   candidate-local
source
measurement_revision
recorded_at
```

`inferred` / `fixture` / `pending` / `invalid` are **not**
ranking evidence. Only `measurement_status=measured` and
`correctness=1` project to v1 `measured=yes`.

Normalizer from frozen `s2c2.measured_storage_cost.v1`:

```text
measured=yes  + source=device-log     →  measured
measured=no   + source=fixture-table  →  fixture
measured=pending                      →  pending
anything else                         →  invalid
```

## Query

```text
ranking-eligible  iff  status=measured ∧ correctness=1
export v1         last ranking-eligible row per
                  (profile, candidate_signature)
                  inside the requested revision/workload slice
```

`s2c2-opt` matching stays:

```text
(profile, candidate_signature)
measured=yes && correctness=1
```

The compiler does not read the Evidence DB, campaign logs,
or `hardware-ledger.jsonl`.

## CLI

```bash
python3 runtime/record_evidence.py --print-evidence-db-contract
python3 runtime/record_evidence.py --ingest-frozen-campaign
python3 runtime/record_evidence.py --check-evidence-db
python3 runtime/record_evidence.py --query-evidence \
  --profile=rtx4090 \
  --workload-signature=ssd-loop-pipeline \
  --measurement-revision=5d-loop-4090
python3 runtime/record_evidence.py --export-measured-v1 \
  --profile=rtx4090 \
  --workload-signature=storage-aware-pipeline \
  --measurement-revision=5a-pipeline-4090 \
  --out table.jsonl
```

`--ingest-measured-v1` accepts only `s2c2.measured_storage_cost.v1`.
Unknown JSON keys are dropped. Hardware-ledger rows are skipped.

## Out of scope

```text
6C capacity-aware residency
6D measured capacity cost
5E rewrite
re-measuring 5A–5D
changing cost-v04 / default-3g / #69
changing loadMeasuredCostTable match keys
C||Storage flatten
invented sibling sched.wait
FileCheck of microseconds
```
