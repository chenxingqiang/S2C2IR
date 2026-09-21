# Capability Applicability schema re-validation

**Status:** design freeze from `e2edff0` (PR #125 merged).
Not a rewrite. Not `sufficient=yes`. Not 6C-M.
Not an expansion of `S2C2CapabilitySchedule.cpp`.
Not a replacement of v3 `CapabilityRecord` pair catalog.
Not a change to frozen occupancy Evidence Algebra.
Does not expand the `capability.*` token set.

```text
Goal     re-validate raw CapabilityApplicability records in derive
Not      sufficiency, authorization, rewrite, or a new Decision subject
Rewrite  still only from an existing capability license
```

PR #125 froze

```text
s2c2.capability_applicability.v1
        ↓
derive_applicable_decision
        ↓
Decision.subject=applicable
```

The constructor `capability_record()` already rejected
`reason.canonical` outside `capability.*`. Derive on a raw
bag did not re-check schema, identity fields, closed
enums, or canonical. A mutated payload could still classify
as `applicable=yes`.

This cut closes that hole. It does **not** compose usable
and applicable into sufficient.

```text
EvidenceRecord
   ↓
Predicate
   ↓
Decision.subject=usable                 FROZEN (#124)
   ↓
Capability / Applicability              FROZEN (#125)
   ↓
raw-record re-validation                ← this freeze
   ↓
Sufficiency                             CLOSED
```

## Architectural constitution

Unchanged:

```text
applicable ≠ usable ≠ sufficient
applicable ≠ rewrite-license
capability.* tokens closed
authorization.* CLOSED
6C-M PARKED
```

```text
Decision.subject=applicable   this cut (same as #125)
Decision.subject=sufficient   NOT emitted
```

## What derive re-checks (in-scope records)

Scope remains `(target, device)` from `identity`. Records
that cannot expose that pair are not in this query (other
device isolation). An in-scope raw record is checked
**before** provenance classification and applicability
classification:

```text
schema              s2c2.capability_applicability.v1
identity fields     target, device, kind
identity == payload target / device / kind
target              cpu|cuda|rocm|sycl|ascend|npu|cim
kind                concurrent-pair|named-nonblocking|staged-dma
applicability       yes|no|n/a
occupancy_usable    yes|no|n/a
provenance          catalog|occupancy-query|unknown
reason.canonical    capability.* closed set
```

Unknown → Preserve / safe no. Derive does not raise
`RuntimeError` on a raw bag.

## Typed reasons (no new capability tokens)

| Defect | Decision.reasons |
| ------ | ---------------- |
| wrong/missing schema, bad applicability, `reason.canonical` outside `capability.*` | `decision.unknown-reason` |
| identity missing or identity ≠ payload | `decision.identity-mismatch` |
| in-scope record `target` / `kind` not in the closed sets | `capability.unknown-target` / `capability.unknown-kind` |
| `provenance` not in the closed set | `capability.missing-evidence` |
| `provenance=unknown` (well-formed) | `capability.missing-evidence` (frozen #125) |

`decision.unknown-reason` is reused from the frozen #123
vocabulary. This cut does **not** add
`decision.schema-mismatch` or `capability.invalid-*`.

A record that claims `reason.canonical=authorization.rewrite`
must **not** copy that token into `Decision.reasons[]`.

```text
authorization.canonical on a raw record
        ≠
Decision.reasons[]
```

## Order (locked)

```text
query unknown target/kind
    ↓
scope by identity (target, device)
    ↓
raw-record re-validation          ← this cut
    ↓
duplicate identity
    ↓
missing record
    ↓
provenance=unknown
    ↓
applicability classification
```

Constructor-built records remain a convenience. Derive
must not trust them: a shallow copy with a mutated field
is still a raw record.

## Negative fixture matrix (added)

| Case | Raw record | Applicable Decision |
| ---- | ---------- | ------------------- |
| invalid-schema | `schema=s2c2.evidence_record.v1`, applicability=yes | `decision.unknown-reason` |
| invalid-canonical | `canonical=authorization.rewrite`, applicability=yes | `decision.unknown-reason` |
| invalid-applicability | `applicability=maybe` | `decision.unknown-reason` |
| invalid-provenance | `provenance=invented`, applicability=yes | `capability.missing-evidence` |

Frozen #125 cases (unknown-provenance, duplicate, identity
mismatch, unknown-kind=`sufficient`, usable ≠ applicable)
stay.

## Out of scope

```text
sufficient=yes print
Decision.subject=sufficient
authorization.* tokens
rewrite-license=yes
rewrite-path / replace / erase
F_storage_schedule
expanding S2C2CapabilitySchedule.cpp
changing 6C-J/K/L printers
changing v3 catalog JSONL
changing 6B Evidence DB identity
changing architecture-healthcheck.md scores
expanding capability.* vocabulary
FileCheck of microseconds
```

## Host contract

```bash
python3 runtime/record_capability_applicability.py --print-capability-applicability-contract
python3 runtime/record_capability_applicability.py --print-capability-applicability-matrix
```

Query-only. `Decision.subject=applicable`.
`raw-record-revalidated yes`. `rewrite-license=no`.

Independent occupancy usable + capability applicable report
(two Decisions; not a conjunction; not sufficient):
[`occupancy-capability-report.md`](occupancy-capability-report.md).
Capability Profile / Applicability aggregation (facts, not
sufficient):
[`capability-profile.md`](capability-profile.md).
Realization Legality (constraint facts copied; not
sufficient / can-run-plan):
[`realization-legality.md`](realization-legality.md).
Realization Checking (claimed-kinds vs frozen legality facts;
not can-run-plan):
[`realization-checking.md`](realization-checking.md).
