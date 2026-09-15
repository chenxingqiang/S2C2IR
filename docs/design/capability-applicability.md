# Capability Applicability (evidence-backed)

**Status:** design freeze from `15895ea` (PR #124 merged).
Not a rewrite. Not `sufficient=yes`. Not 6C-M.
Not an expansion of `S2C2CapabilitySchedule.cpp`.
Not a replacement of v3 `CapabilityRecord` pair catalog.
Not a 6B Evidence DB identity change.

```text
Goal     freeze Capability / Applicability as the next layer
         after Evidence → Predicate → Decision
Not      sufficiency, authorization, rewrite, or a new F
Rewrite  still only from an existing capability license
```

Occupancy Evidence Algebra answers *usable* for a
`(selected, object)` domain. This cut answers a different
question:

```text
Is this capability evidence-backed on this target/device?
```

It does **not** answer “therefore sufficient?”.

```text
Evidence
   ↓
Predicate
   ↓
Decision.subject=usable          FROZEN (#124)
   ↓
Capability / Applicability       ← this freeze
   ↓
Sufficiency                      CLOSED
   ↓
Authorization                    CLOSED
   ↓
Rewrite                          CLOSED
```

## Architectural constitution

Unchanged occupancy invariants, plus:

```text
Capability  ≠  Sufficiency
Capability  ≠  Authorization
Capability  ≠  Rewrite
applicable  ≠  usable
applicable  ≠  rewrite-license
```

```text
Decision.subject=applicable   this cut
Decision.subject=usable       occupancy only (not emitted here)
Decision.subject=sufficient   NOT emitted
authorization.*               CLOSED
6C-M                          PARKED
```

Unknown target, device, or kind → safe no / Preserve.

## Why not sufficient next

A lone

```text
sufficient = usable ∧ dest-invalidation ∧ applicable ∧ …
```

is still the wrong next cut. Occupancy usable and hardware
applicability are different questions. Composing them into
one boolean would hide *which* question failed and reopen
6C-M.

v3 `CapabilityRecord` (pair / depth / memory / sync) stays
the **catalog cell**. This freeze is the **applicability
Decision** that may cite a cell. They must not share a
schema.

```text
v3 CapabilityRecord              ≠  s2c2.capability_applicability.v1
pair catalog cell                ≠  evidence-backed applicable Decision
S2C2CapabilitySchedule.cpp       ≠  this module
```

## Identity (aligned with derivation)

```text
CapabilityApplicability.identity = (target, device, kind)
derive_applicable_decision(records, target, device, kind)
```

Derivation **scope equals identity**. There is no hidden
`dict[kind]` last-writer-wins. 0 or 1 record per identity.

```text
duplicate identity     → decision.duplicate-identity
identity.kind ≠ kind
identity.device ≠ device
identity.target ≠ target
                       → decision.identity-mismatch
```

`identity.*` must match the payload fields. Disagreement is
host-path **safe no**, not a user-facing `RuntimeError`.

This identity is **not** 6B `E` and **not** occupancy
`(selected, kind, object)`.

## Closed vocabularies this cut

Targets:

```text
cpu | cuda | rocm | sycl | ascend | npu | cim
```

These names attach existing profiles. This cut does **not**
add a dialect, adapter, or schedule pass.

Capability kinds (existence, not sufficient):

```text
concurrent-pair      named pair may overlap on this device
named-nonblocking    named nonblocking sync model exists
staged-dma           staged DMA / StageOrder transfer exists
```

`restore-target` / `live-bytes` / `alias` / `lifetime` stay
occupancy reservations. They are not capability kinds here.

`capability.*` reason tokens (closed):

| Token | Meaning |
| ----- | ------- |
| `capability.present` | evidence-backed existence on this identity |
| `capability.missing-evidence` | no record in scope, or `provenance=unknown` |
| `capability.not-applicable` | record says no |
| `capability.unknown-target` | target not in the closed set |
| `capability.unknown-kind` | kind not in the closed set |

`authorization.*` remains empty. Do not invent ad-hoc
reason strings.

## Schema `s2c2.capability_applicability.v1`

All fields required. Not ingested by `s2c2-opt` this cut.

```text
identity        (target, device, kind)
target          closed target token
device          opaque id (sm89:rtx4090, ascend910b, host, …)
kind            concurrent-pair | named-nonblocking | staged-dma
applicability   yes | no | n/a
provenance      catalog | occupancy-query | unknown
occupancy_usable  yes | no | n/a   (input fact; not a Decision)
reason.canonical  capability.*
reason.display    short token
```

```text
occupancy_usable=yes  ≠  applicable=yes
dest-invalidation=yes ≠  applicable=yes
applicable=yes        ≠  sufficient=yes
applicable=yes        ≠  rewrite-license=yes
```

`occupancy_usable` may cite a frozen occupancy Decision. It
is evidence input. It does not become `Decision.subject`.

Unknown provenance is not catalog evidence and not an
occupancy query. Derive treats it as missing evidence
**before** reading `applicability`:

```text
provenance=unknown
  → Decision.subject=applicable
    result=no
    reasons=capability.missing-evidence
```

even when the record claims `applicability=yes`.
Do not expand the capability token set for this case.

## Deterministic applicable Decision

```text
Decision.subject = applicable
```

Query arguments `(target, device, kind)` that are not in
the closed sets:

```text
unknown target → result=no reasons=capability.unknown-target
unknown kind   → result=no reasons=capability.unknown-kind
```

Otherwise, consume the unique record whose identity equals
the query:

```text
no record
  → result=no
    reasons=capability.missing-evidence

duplicate identity
  → result=no
    reasons=decision.duplicate-identity

identity/payload mismatch
  → result=no
    reasons=decision.identity-mismatch

provenance=unknown
  → result=no
    reasons=capability.missing-evidence

applicability=n/a
  → result=n/a
    reasons=[]

applicability=yes
  → result=yes
    reasons=capability.present

applicability=no
  → result=no
    reasons=reason.canonical from the record
```

Records for another `target` or `device` do not fill a
missing identity. Last-writer-wins is forbidden.

Forced:

```text
Decision.subject=applicable   this cut
Decision.subject=sufficient   NOT emitted
Decision.reasons[]            never occupancy display strings
Decision.reasons[]            never evidence.scope-mismatch family
sufficiency-evaluation        n/a
rewrite-license               no
rewrite-path                  no
```

This cut does **not** print from `s2c2-opt`. Existing
`--s2c2-capability-query` / `--s2c2-capability-schedule`
stay as they are. Do **not** fold this algebra into
`S2C2CapabilitySchedule.cpp`.

## Negative fixture matrix

| Case | Query / records | Applicable Decision |
| ---- | --------------- | ------------------- |
| cuda-pair-present | cuda / sm89:rtx4090 / concurrent-pair yes, provenance=catalog | `result=yes` `capability.present` |
| missing-evidence | cuda identity, empty bag | `capability.missing-evidence` |
| unknown-provenance | same identity, applicability=yes, provenance=unknown | `result=no` `capability.missing-evidence` |
| unknown-target | target=`invented` | `capability.unknown-target` |
| unknown-kind | kind=`sufficient` | `capability.unknown-kind` |
| usable-ne-applicable | occupancy_usable=yes, applicability=no | `result=no`; not usable Decision |
| dest-inv-ne-applicable | dest-invalidation cited, no cap evidence | `capability.missing-evidence` |
| ignore-other-device | other device has present | this device still missing-evidence |
| duplicate-identity | two records same identity | `decision.duplicate-identity` |
| identity-kind-mismatch | identity.kind ≠ payload kind | `decision.identity-mismatch` |
| ascend-dma-present | ascend / staged-dma yes | `capability.present` |
| cpu-pair-not-applicable | cpu / concurrent-pair no | `capability.not-applicable` |

`kind=sufficient` as a query is **unknown-kind**, not a
sufficient Decision.

## God object

```text
Capability applicability   this host module
v3 CapabilityRecord        frozen pair catalog
Capability schedule        frozen pair-license host; do not expand
Occupancy Evidence Algebra frozen usable Decision
6B Evidence DB             frozen measured identity E
```

## Out of scope

```text
sufficient=yes print
Decision.subject=sufficient
Decision.subject=usable from this printer
authorization.* tokens
rewrite-license=yes
rewrite-path / replace / erase
F_storage_schedule
expanding S2C2CapabilitySchedule.cpp
changing 6C-J/K/L printers
changing v3 catalog JSONL
changing 6B Evidence DB identity
changing architecture-healthcheck.md scores
FileCheck of microseconds
new vendor adapters
```

## Host contract

```bash
python3 runtime/record_capability_applicability.py --print-capability-applicability-contract
python3 runtime/record_capability_applicability.py --print-capability-applicability-matrix
```

Query-only. `Decision.subject=applicable`.
`rewrite-license=no`. Diagnostic occupancy `--capacity`
does not print these prefixes.

Raw-record re-validation in derive (schema / identity /
closed enums / canonical; not sufficient):
[`capability-applicability-schema.md`](capability-applicability-schema.md).
