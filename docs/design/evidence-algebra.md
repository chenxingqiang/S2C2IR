# Evidence Algebra (machine-readable closure)

**Status:** design freeze from `a539418` (PR #123 merged).
Not a rewrite. Not `sufficient=yes`. Not 6C-M.
Not a change to 6C-J/K/L occupancy printers.
Not an expansion of `S2C2CapabilitySchedule.cpp`.
Not a 6B Evidence DB identity change.

```text
Goal     freeze EvidenceRecord + canonical≠display + usable derivation
Not      sufficiency, license, rewrite, or new occupancy kinds
Rewrite  still only from an existing capability license
```

Stage A froze Decision *shape*. The vocabulary freeze
closed `namespace.local` tokens. This cut makes
`Evidence → Predicate → Decision` **machine-readable**:
records have identity, applicability, provenance, a
canonical reason distinct from the frozen 6C display
string, and a deterministic usable Decision.

## Architectural constitution

Unchanged:

```text
1. HB_source is semantic truth
2. Realization does not change HB
3. Unknown → safe no / Preserve
4. Evidence ≠ authorization
5. Query ≠ rewrite
6. source-data
     ≠ restore-ordering
     ≠ dest-invalidation
     ≠ sufficient
     ≠ rewrite-license
```

```text
6C-J/K/L              occupancy kinds (FROZEN printers)
usable                predicate (not a kind)
Decision.subject      usable only
Decision.subject=sufficient   NOT emitted
authorization.*       CLOSED
6C-M                  PARKED
```

## Why this cut (not 6C-M)

The vocabulary freeze grouped three occupancy display
strings under one algebra token:

```text
unknown-scope
replica-scope-mismatch
destination-scope-mismatch
        ↓
evidence.scope-mismatch
```

That is a **family**, not a canonical failure. Distinct
failure semantics must remain distinct when an analyzer
consumes records. This cut splits them without retargeting
6C printers and without opening sufficiency.

## Schemas (do not collapse)

```text
s2c2.evidence.v1            6B measured ranking row
s2c2.evidence_kind.v1       Stage A kind field list
s2c2.evidence_record.v1     this cut: machine-readable record
s2c2.decision.v1            subject + result + reasons[]
```

```text
s2c2.evidence.v1
  ≠ s2c2.evidence_kind.v1
  ≠ s2c2.evidence_record.v1
```

## EvidenceRecord (`s2c2.evidence_record.v1`)

All fields required. Not ingested by `s2c2-opt` this cut.

```text
identity        (selected, kind, object)
kind            source-data | restore-ordering | dest-invalidation
object          occupancy id; n/a if unused
witness         token; unknown → no
scope           token; unknown → no
applicability   yes | no | n/a
provenance      spec | occupancy-query | unknown
reason.canonical    evidence.*  (Decision / analyzer)
reason.display      frozen 6C printer string
reason.family       grouping token or n/a
```

```text
identity  ≠  6B E = (profile, workload, candidate, revision)
canonical ≠  display
family    ≠  canonical
family    is not a Decision reason
```

Unknown witness, unknown scope, or `provenance=unknown`
⇒ `applicability=no`. Unknown does not invent a validity
FSM.

Classified kinds remain 6C-J/K/L. Reserved, not classified:
`restore-target`, `live-bytes`, `alias`, `lifetime`.

### Identity

```text
EvidenceRecord.identity = (selected, kind, object)
```

`selected` is a capacity-plan identity or `n/a`.
`object` normalizes `tileN` to `N`. Two records with the
same identity are the same occupancy proof; they are not
a 6B measured row.

In any derivation scope `(selected, object)` there is at
most one record per `kind`. A second record with the same
`(selected, kind, object)` is `decision.duplicate-identity`,
not an overwrite.

`identity.kind` must equal the payload `kind`, and
`identity.object` must equal the payload `object`. A
disagreement is `decision.identity-mismatch` (safe no),
not a `RuntimeError` on the host path.

## Canonical vs display vs family

`reason.display` is the frozen 6C-J/K/L `reason=` string.
This cut does **not** retarget those printers.

`reason.canonical` is the typed token an analyzer must
use. Display strings that previously collapsed to
`evidence.scope-mismatch` now have **distinct**
canonicals:

| Display (6C, unchanged) | Canonical | Family |
| ----------------------- | --------- | ------ |
| `unknown-scope` | `evidence.unknown-scope` | `evidence.scope-mismatch` |
| `replica-scope-mismatch` | `evidence.replica-scope-mismatch` | `evidence.scope-mismatch` |
| `destination-scope-mismatch` | `evidence.destination-scope-mismatch` | `evidence.scope-mismatch` |

`evidence.scope-mismatch` is a **family** only. It is not
a canonical reason and MUST NOT appear in
`Decision.reasons[]`.

Other displays remain 1:1 with the vocabulary freeze
(`unknown-witness` → `evidence.unknown-witness`, …).

New canonical locals this cut (still `evidence.*`):

```text
evidence.unknown-scope
evidence.replica-scope-mismatch
evidence.destination-scope-mismatch
```

They follow the existing `namespace.local` grammar.
Implementations MUST NOT invent further locals here.

## Provenance

| `provenance` | Meaning |
| ------------ | ------- |
| `spec` | occupancy spec fixture supplied the accepted witness |
| `occupancy-query` | occupancy query without that spec witness |
| `unknown` | witness/scope/provenance not known → no |

`provenance` is not authorization and not a 6B measurement
revision.

## Deterministic usable Decision

Derivation is scoped to one occupancy proof domain:

```text
derive_usable_decision(records, selected, object)
usable(selected, object) = source-data ∧ restore-ordering
Decision.subject = usable
```

Only records with `identity.selected` and `identity.object`
equal to the derivation arguments are consumed.
`dest-invalidation` records in that scope are ignored for
the predicate, but still counted toward uniqueness.

```text
0 or 1 record per (selected, kind, object) in scope
duplicate identity → result=no
                     reasons=decision.duplicate-identity
                     (safe no; not last-writer-wins)
```

Derivation (total, deterministic):

```text
duplicate (selected, kind, object) in scope
  → result=no
    reasons=decision.duplicate-identity

identity.kind ≠ payload kind
(or identity.object ≠ payload object)
  → result=no
    reasons=decision.identity-mismatch

missing source-data or restore-ordering record in scope
  → result=no
    reasons=predicate.missing-input

both applicability=n/a
  → result=n/a
    reasons=[]          (empty allowed only on n/a)

both applicability=yes
  → result=yes
    reasons=predicate.source-data-present,
            predicate.restore-ordering-present

otherwise
  → result=no
    reasons=canonical of each non-yes usable kind
            (stable kind order: source-data, restore-ordering)
```

Records for another `selected` or `object` do not fill a
missing usable kind. Last writer of `dict[kind]` is not a
Decision.

Forced:

```text
derive scope                  (selected, object)
identity cardinality          0 or 1 per (selected, kind, object)
duplicate identity            safe no (decision.duplicate-identity)
identity.kind ≠ payload kind  safe no (decision.identity-mismatch)
last-writer-wins              forbidden
dest-invalidation record      does not enter this Decision
Decision.reasons[]            canonical / predicate.* /
                              decision.duplicate-identity /
                              decision.identity-mismatch
Decision.reasons[]            never evidence.scope-mismatch
Decision.reasons[]            never reason.display
Decision.subject=sufficient   NOT emitted
sufficiency-evaluation        n/a
rewrite-license               no
rewrite-path                  no
```

Reasons on `result=no` are never empty. Kind order in
`reasons[]` is stable: `source-data` then
`restore-ordering` then `predicate.missing-input` when
used.

This cut does **not** print a per-EVICT Decision from
`s2c2-opt`. Existing 6C prefixes remain the occupancy
printers. The host matrix below freezes derivation.

## Negative fixture matrix

Host-locked cases (query-only). Display strings stay the
6C names; canonicals must not collapse.

| Case | Records | Usable Decision |
| ---- | ------- | --------------- |
| dest-inv-yes-usable-yes | three kinds yes | `result=yes`; dest canonical absent from reasons |
| source-unknown-scope | source-data `unknown-scope` | `reasons` contains `evidence.unknown-scope`; not family |
| replica-scope-mismatch | source-data replica mismatch | `evidence.replica-scope-mismatch`; not unknown-scope |
| dest-scope-mismatch-usable-yes | usable yes; dest display mismatch | usable still yes; dest canonical absent |
| missing-ordering | source-data only | `predicate.missing-input` |
| unknown-witness | source-data unknown witness | `evidence.unknown-witness` |
| both-n/a | both kinds n/a | `result=n/a`; empty reasons |
| ignore-other-selected | S0 source-data yes + S1 usable yes | S0 still `predicate.missing-input` |
| ignore-other-object | object=2 source-data yes + object=3 usable yes | object=2 still `predicate.missing-input` |
| duplicate-identity | two source-data same identity | `decision.duplicate-identity`; not last-writer-wins |
| identity-kind-mismatch | `identity.kind=restore-ordering` but payload `kind=source-data` | `decision.identity-mismatch`; not usable yes |

Pairwise: the three scope canonicals are distinct. A
replica mismatch must not derive `evidence.unknown-scope`
or `evidence.destination-scope-mismatch`.

## God object

Do **not** fold EvidenceRecord / derivation into
`S2C2CapabilitySchedule.cpp`. Do **not** retarget 6C-J/K/L
`reason=` printers.

```text
Evidence algebra     later: dedicated analysis module
Capability schedule  frozen pair-license / occupancy query host
6B Evidence DB       frozen measured identity E
```

## Out of scope

```text
sufficient=yes print
Decision.subject=sufficient
authorization.* tokens
retargeting 6C-J/K/L reason= strings
restore-target / live-bytes / alias / lifetime classifiers
rewrite-license=yes
rewrite-path / replace / erase
F_storage_schedule
expanding S2C2CapabilitySchedule.cpp
changing 6B Evidence DB identity
changing architecture-healthcheck.md scores
FileCheck of microseconds
```

## Host contract

```bash
python3 runtime/record_decision.py --print-evidence-algebra-contract
python3 runtime/record_decision.py --print-evidence-algebra-matrix
```

Query-only. `Decision.subject=usable`.
`canonical ≠ display`. `evidence.scope-mismatch` is family
only. Diagnostic `--capacity` does not print these
prefixes.

Capability / Applicability (evidence-backed; not sufficient):
[`capability-applicability.md`](capability-applicability.md).
Raw-record re-validation of that schema in derive:
[`capability-applicability-schema.md`](capability-applicability-schema.md).
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
