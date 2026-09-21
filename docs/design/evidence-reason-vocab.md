# Reason Vocabulary / Evidence Schema Closure

**Status:** design freeze from `23d3a03` (PR #122 merged).
Not a rewrite. Not `sufficient=yes`. Not 6C-M.
Not a change to 6C-J/K/L occupancy printers.
Not an expansion of `S2C2CapabilitySchedule.cpp`.

```text
Goal     close typed reason namespaces and evidence/decision fields
Not      a giant sufficient AND, license, rewrite, or new kinds
Rewrite  still only from an existing capability license
```

Stage A froze Decision *shape* (`subject` + `result` +
`reasons[]`). This cut freezes which tokens may appear in
`reason` / `reasons[]`, and which fields those schemas
carry. Occupancy printer strings stay as 6C froze them.

## Architectural constitution

Unchanged from Stage A:

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
Decision.subject          required
this cut emits            Decision.subject=usable only
this cut does not emit    Decision.subject=sufficient
authorization.*           CLOSED (empty)
6C-M                      PARKED
```

## Grammar

```text
reason-token = namespace "." local
namespace    = evidence | predicate | decision | authorization
local        = [a-z0-9]+(-[a-z0-9]+)*
```

A string that is not `namespace.local`, or whose
`(namespace, local)` pair is not in the tables below, is
**not** a typed reason. Unknown → no / Preserve.
Implementations MUST NOT invent tokens.

## Namespaces

| Namespace | Answers | This cut |
| --------- | ------- | -------- |
| `evidence.*` | why a kind is applicable or not | closed table |
| `predicate.*` | why a named predicate holds or lacks input | closed table |
| `decision.*` | Decision record well-formedness | closed table |
| `authorization.*` | license / rewrite | **empty; CLOSED** |

`authorization.*` has no tokens **on the Stage A / EA-1
printer**. Emitting one from occupancy classification
would be a license. That printer stays empty.

## 7A `authorization.*` v0.1

7A opens this namespace for the AuthorizationEvaluator
only. See [`authorization-boundary.md`](authorization-boundary.md).

```text
Stage-A / EA-1     authorization.* = empty
7A evaluator       authorization.* v0.1
emitting a token   ≠  rewrite-license=yes
emitting a token   ≠  rewrite-path=yes
```

| Token | Meaning |
| ----- | ------- |
| `authorization.sufficient-no` | sufficient result is not yes |
| `authorization.policy-mismatch` | policy name is not v0.1 |
| `authorization.policy-unknown` | policy result is not yes/no/n/a |
| `authorization.provenance-unknown` | provenance is not known |
| `authorization.action-mismatch` | claimed action ≠ target identity.action |
| `authorization.identity-mismatch` | 7A scope (selected / object / action / license-kind) disagrees with the evaluator identity |
| `authorization.duplicate-license` | more than one `rewrite-license` input |
| `authorization.authorized-no` | rewrite-license asked but authorized=no |
| `authorization.authorized-closed` | authorized=yes under Policy v0.1 |
| `authorization.rewrite-license-missing` | authorized=yes and no license input |
| `authorization.rewrite-license-no` | explicit license result=no |
| `authorization.rewrite-license-closed` | rewrite-license=yes; query-only, rewrite-path stays no |

7A does **not** reopen frozen `decision.*`. Stage-A
well-formedness stays on that table. 7A policy / action /
license semantics stay on `authorization.*`:

```text
duplicate REQUIRED        → decision.duplicate-identity
unknown token             → decision.unknown-reason
7A scope mismatch         → authorization.identity-mismatch
>1 rewrite-license        → authorization.duplicate-license
claimed ≠ target action   → authorization.action-mismatch
authorized=yes            → authorization.authorized-closed
rewrite-license=yes       → authorization.rewrite-license-closed
```

`record_decision.py --print-evidence-reason-vocab` still
prints `authorization-tokens=none`. 7A prints the v0.1
table from `record_authorization.py`.

## `evidence.*` (closed)

These tokens classify occupancy-kind evidence. They do
**not** replace the 6C-J/K/L printer strings; they name
the algebra those printers already inhabit.

| Token | Meaning |
| ----- | ------- |
| `evidence.unknown-witness` | witness token not in the accepted set |
| `evidence.scope-mismatch` | scope / replica / destination does not match occupancy |
| `evidence.no-source-replica` | no TRANSFER source replica |
| `evidence.no-validity-witness` | replica exists; no source-data witness |
| `evidence.no-ordering-witness` | source-data yes or n/a; no restore-at-point witness |
| `evidence.no-invalidation-witness` | usable may be yes; no dest-invalidation witness |
| `evidence.interval-does-not-cover` | replica live does not cover occupancy live |
| `evidence.not-before-consumer` | restore point is not `occ.end` |
| `evidence.witnessed-unmutated-cover` | accepted source-data witness |
| `evidence.witnessed-before-consumer` | accepted restore-ordering witness |
| `evidence.witnessed-drop-stale` | accepted dest-invalidation witness |

### Occupancy printer map (6C strings unchanged)

| 6C printer `reason=` | Algebra token |
| -------------------- | ------------- |
| `unknown-witness` | `evidence.unknown-witness` |
| `unknown-scope` | `evidence.scope-mismatch` |
| `replica-scope-mismatch` | `evidence.scope-mismatch` |
| `destination-scope-mismatch` | `evidence.scope-mismatch` |
| `no-source-replica` | `evidence.no-source-replica` |
| `no-validity-witness` | `evidence.no-validity-witness` |
| `no-ordering-witness` | `evidence.no-ordering-witness` |
| `no-invalidation-witness` | `evidence.no-invalidation-witness` |
| `interval-does-not-cover` | `evidence.interval-does-not-cover` |
| `not-before-consumer` | `evidence.not-before-consumer` |
| `witnessed-unmutated-cover` | `evidence.witnessed-unmutated-cover` |
| `witnessed-before-consumer` | `evidence.witnessed-before-consumer` |
| `witnessed-drop-stale` | `evidence.witnessed-drop-stale` |

This cut does **not** retarget `s2c2-opt` prefixes. The map
is the schema, not a rewrite of frozen classification.

## `predicate.*` (closed)

| Token | Meaning |
| ----- | ------- |
| `predicate.missing-input` | named predicate lacks a required kind |
| `predicate.source-data-present` | `source-data=yes` fed `usable` |
| `predicate.restore-ordering-present` | `restore-ordering=yes` fed `usable` |

Stage A Decision example, namespaced:

```text
Decision
  subject=usable
  result=yes
  reasons=predicate.source-data-present,
          predicate.restore-ordering-present
```

`dest-invalidation=yes` is still an evidence record, not a
predicate reason on `usable` and not a sufficient Decision.

## `decision.*` (closed)

| Token | Meaning |
| ----- | ------- |
| `decision.subject-required` | `result` without `subject` is not a Decision |
| `decision.unknown-subject` | `subject` not in the closed subject set |
| `decision.unknown-reason` | `reasons[]` contains a token outside this vocabulary |
| `decision.duplicate-identity` | more than one EvidenceRecord for the same `(selected, kind, object)` |
| `decision.identity-mismatch` | `identity.kind` or `identity.object` disagrees with the payload |

Not in the Stage A occupancy vocabulary (forbidden on EA-1):

```text
sufficient-not-composed
decision.subject-sufficient
authorization.* on record_decision.py
ad-hoc free-form strings
```

## Schema freeze

`s2c2.evidence_kind.v1` fields (all required):

```text
kind            token; classified or reserved (see Stage A)
object          occupancy id; n/a if unused
witness         token; unknown → no
scope           token; unknown → no
applicability   yes | no | n/a
reason          evidence.* token; never empty on no
```

Classified kinds remain `source-data`, `restore-ordering`,
`dest-invalidation`. Reserved, not classified:
`restore-target`, `live-bytes`, `alias`, `lifetime`.

`s2c2.decision.v1` fields (all required):

```text
subject    named predicate; this cut: usable only
result     yes | no | n/a
reasons[]  typed tokens from this vocabulary
```

```text
Decision.subject=usable
  ≠ Decision.subject=sufficient
this cut does not emit Decision.subject=sufficient
sufficiency-evaluation=n/a
```

## God object

Do **not** fold the vocabulary into
`S2C2CapabilitySchedule.cpp`. Do **not** retarget 6C-J/K/L
`reason=` printers in this cut.

```text
Evidence / Decision / reasons   later: dedicated analysis module
Capability schedule             frozen pair-license / occupancy query host
6B Evidence DB                  frozen measured identity E
```

## Out of scope

```text
sufficient=yes print from EA-1 / 6C-I
Decision.subject=sufficient from record_decision.py
authorization.* tokens from EA-1
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
python3 runtime/record_decision.py --print-evidence-reason-vocab
```

Query-only. `Decision.subject=usable`.
`authorization-tokens=none`. `rewrite-license=no`.
`rewrite-path=no`. Diagnostic `--capacity` does not print
this prefix.

Machine-readable EvidenceRecord, canonical ≠ display, and
usable Decision derivation:
[`evidence-algebra.md`](evidence-algebra.md).
