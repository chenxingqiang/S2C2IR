# Occupancy / Capability independent report

**Status:** design freeze from `fd33212` (PR #126 merged).
Not a rewrite. Not `sufficient=yes`. Not 6C-M.
Not a generic schema validator.
Not an expansion of `S2C2CapabilitySchedule.cpp`.
Not a conjunction of usable and applicable.

```text
Goal     report Decision.usable and Decision.applicable independently
Not      sufficient = usable ∧ applicable ∧ …
Rewrite  still only from an existing capability license
```

#125/#126 answer *applicable* on `(target, device, kind)`.
#124 answers *usable* on `(selected, object)`. Those are
different questions. This cut freezes a **report** that
places the two Decisions next to each other without
AND-ing them.

```text
EvidenceRecord
   ↓
Predicate
   ↓
Decision.subject=usable                 FROZEN (#124)
   ↓
Capability / Applicability              FROZEN (#125/#126)
   ↓
independent report                      ← this freeze
   ↓
Sufficiency                             CLOSED
```

## Why this cut (and not sufficient)

```text
sufficient = usable ∧ dest-invalidation ∧ applicable ∧ …
```

is still the wrong next cut. A conjunction hides *which*
question failed and reopens 6C-M.

```text
usable=yes ∧ applicable=yes  ≠  sufficient=yes
usable=yes ∧ applicable=no   names the applicable failure
usable=no  ∧ applicable=yes  names the usable failure
```

The report is **not** a Decision.

```text
s2c2.occupancy_capability_report.v1  ≠  s2c2.decision.v1
Decision.subject=sufficient          NOT emitted
sufficiency-evaluation               n/a
rewrite-license                      no
rewrite-path                         no
```

## Identities stay distinct

```text
usable identity      = (selected, object)
applicable identity  = (target, device, kind)
```

The report carries both. It does not invent a joint
identity and does not let one bag fill the other.

```text
occupancy_usable field on a CapabilityApplicability record
        ≠
Decision.subject=usable
```

`occupancy_usable=no` with occupancy EvidenceRecords that
derive `usable=yes` still yields `usable=yes`. The field
is a citation, not the occupancy Decision.

dest-invalidation remains an occupancy kind counted for
uniqueness. It still does not enter the usable Decision
and does not create sufficient.

## Schema `s2c2.occupancy_capability_report.v1`

All fields required. Query-only. Not ingested by `s2c2-opt`.

```text
schema
usable-identity       (selected, object)
applicable-identity   (target, device, kind)
usable                s2c2.decision.v1 subject=usable
applicable            s2c2.decision.v1 subject=applicable
sufficiency-evaluation n/a
rewrite-license       no
rewrite-path          no
```

Derivation **calls** the frozen functions; it does not
reimplement them:

```text
derive_usable_decision(...)
derive_applicable_decision(...)
```

#126 raw-record re-validation stays in the applicable
path. This cut does **not** open a generic schema
validator and does **not** change
`malformed-but-out-of-scope` handling.

## Negative fixture matrix

| Case | Occupancy / capability | Report |
| ---- | ---------------------- | ------ |
| both-yes-ne-sufficient | usable yes (incl. dest-inv) + applicable yes | two yes Decisions; `sufficiency-evaluation=n/a` |
| usable-yes-applicable-no | usable yes + applicability=no | usable yes, applicable no; not AND-hidden |
| usable-no-applicable-yes | missing restore-ordering + applicable yes | usable no, applicable yes |
| dest-inv-ne-sufficient | dest-invalidation=yes + both yes | dest canonical absent from usable reasons; still not sufficient |
| occupancy-field-ne-usable-decision | occupancy records yes; `occupancy_usable=no` on cap record | usable still yes; field ≠ Decision |

## God object

```text
this host module           independent report
occupancy Evidence Algebra frozen usable Decision
Capability applicability   frozen applicable Decision
Capability schedule        frozen pair-license host; do not expand
6B Evidence DB             frozen measured identity E
```

## Out of scope

```text
sufficient=yes print
Decision.subject=sufficient
usable ∧ applicable conjunction
authorization.* tokens
generic schema validator
malformed-but-out-of-scope vs valid-but-different-scope
rewrite-license=yes
rewrite-path / replace / erase
F_storage_schedule
expanding S2C2CapabilitySchedule.cpp
changing 6C-J/K/L printers
changing v3 catalog JSONL
changing 6B Evidence DB identity
changing architecture-healthcheck.md scores
FileCheck of microseconds
```

## Host contract

```bash
python3 runtime/record_occupancy_capability.py --print-occupancy-capability-report-contract
python3 runtime/record_occupancy_capability.py --print-occupancy-capability-report-matrix
```

Query-only. Two Decisions. `rewrite-license=no`.
Diagnostic occupancy `--capacity` does not print these
prefixes.
