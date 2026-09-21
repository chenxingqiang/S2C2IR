# 7B Storage Rewrite Plan

**Status:** design/open for `Decision.subject=rewrite-plan`.
Not frozen until `PR #138 — APPROVED`.
Not an IR rewrite. Not `applySchedule`. Not an
`F_storage_schedule` inhabitant. Not an expansion of
`S2C2CapabilitySchedule.cpp`. Does not change the frozen
6C-M or 7A evaluators.

```text
Goal     name the unique licensed storage rewrite
Not      if rewrite-license: rewrite-path = yes
Rewrite  still not applied; rewrite-path stays no
```

7A froze `Decision.subject=authorized` and
`Decision.subject=rewrite-license`
([`authorization-boundary.md`](authorization-boundary.md)).
This cut is the third door. It consumes that envelope. It
does **not** re-evaluate sufficient / policy / provenance /
action-match.

Product lock: [`compiler-spine.md`](compiler-spine.md).

## One question

```text
When rewrite-license=yes already holds for
(selected, object, action, license-kind), what is the
unique storage rewrite this compiler may name?
```

```text
rewrite-license
    │
    ▼
Rewrite Planner
    │
    ├── 7A envelope
    ├── RewritePlanIdentity
    └── unique sequence v0.1
    │
    ▼
rewrite-plan
    │
    ▼
STOP  (applied=no)
```

## Three subjects stay distinct

```text
rewrite-license   May the compiler name this class of rewrite?
rewrite-plan      Is the unique KEEP→EVICT→TRANSFER→RESTORE
                  sequence selected for this identity?
rewrite-path      Does an IR rewrite exist and is it applied?
```

```text
rewrite-license        ≠  rewrite-plan
rewrite-plan           ≠  rewrite-path
rewrite-plan=yes       ≠  applied=yes
rewrite-plan=yes       ≠  can-run-plan=yes
```

Never:

```text
if rewrite-license:
    rewrite-path = yes
```

Never:

```text
if rewrite-plan:
    applySchedule / replace / erase
```

## RewritePlanIdentity

7A license identity is already
`(selected, object, action, license-kind)`. The plan is
the same question's unique inhabitant, so it uses the
same four-tuple.

```text
RewritePlanIdentity = (selected, object, action, license-kind)
action v0.1         = storage-rewrite
license-kind v0.1   = storage-capacity-rewrite
```

```text
authorized(S0, O2, storage-rewrite)
        ≠
rewrite-plan(S0, O2, storage-rewrite, storage-capacity-rewrite)
```

The latter requires:

```text
rewrite-license = yes
identity        = (S0, O2, storage-rewrite)
license-kind    = storage-capacity-rewrite
sequence        = KEEP → EVICT → TRANSFER → RESTORE
```

Later `schedule-rewrite` / `device-placement` get their
own plans. They must not share this sequence.

This is **not** \(F_{\mathrm{storage\_schedule}}\). That
family is prefetch × depth × residency × capacity and
stays a separate design-only draft (`#135`). 7B names one
licensed sequence. It does not inhabit the product.

## Sequence v0.1

One rewrite only:

```text
KEEP → EVICT → TRANSFER → RESTORE
```

```text
KEEP      objects that remain in the fast space
EVICT     objects that leave the fast space
TRANSFER  restore realization for every EVICT object
RESTORE   occupancy of the restore target after TRANSFER
```

Not PREFETCH. Not PRESERVE. Not REMATERIALIZE. Not
concurrent sibling reorder (already a frozen transform
witness). Not a Cost ranking over F(site).

`rewrite-sequence` is a **counted input**, not an ignored
extra:

```text
0 sequence    → unique v0.1 sequence
1 sequence    → must equal KEEP→EVICT→TRANSFER→RESTORE
>1 sequence   → rewrite.duplicate-sequence
```

First-seen sequence must not win.

## Planner vs AuthorizationEvaluator

```text
7A scope     (selected, object, action)
7A license   (selected, object, action, license-kind)
7B scope     (selected, object, action, license-kind)
```

The 7A envelope identity must match
`(selected, object, action)`. The license-identity must
match the four-tuple. If `rewrite-license` carries its
own `identity`, it must equal `license-identity` and the
planner four-tuple. Frozen 7A Decisions may omit that
field; absence is not a failure. Disagreement is
`rewrite.identity-mismatch`, not Stage-A
`decision.identity-mismatch` and not 7A
`authorization.identity-mismatch`.

Consume is **producer-contract validation**, not
re-evaluation:

```text
schema               = s2c2.authorization.v1
source-schema        = s2c2.decision.v1
authorized           = Decision schema/subject/result
rewrite-license      = Decision schema/subject/result
license=yes ⇒ authorized=yes
```

Unknown / malformed Decision shape or `source-schema` is
`decision.unknown-reason`. 7B does **not** re-evaluate
sufficient / policy / provenance / action-match.

0 / 1 / >1 authorization envelopes:

```text
0 envelope    → predicate.missing-input
1 envelope    → evaluate license + identity + sequence
>1 envelope   → rewrite.duplicate-envelope
```

Other extra subjects, including duplicate extras, are
ignored.

## Decisions

```text
Decision
  schema     s2c2.decision.v1
  subject    rewrite-plan
  result     yes | no
  reasons[]  typed tokens
```

The planner does **not** emit `result=n/a`.

On `rewrite-plan=yes`:

```text
reasons        = rewrite.plan-closed
sequence       = KEEP, EVICT, TRANSFER, RESTORE
transformation = keep-evict-transfer-restore
applied        = no
rewrite-path   = no
can-run-plan   = no
```

`transformation` names the sequence. It does **not** apply
it. `rewrite-path` stays `no` until a later IR cut.

Guardrails:

```text
rewrite-license=no                  → rewrite-plan=no / license-no
authorized=no                       → rewrite-plan=no / license-no
malformed authorized/license        → rewrite-plan=no / unknown-reason
source-schema ≠ 7A producer         → rewrite-plan=no / unknown-reason
identity ≠ planner scope            → rewrite-plan=no / identity-mismatch
rewrite-license.identity ≠ license-identity
                                    → rewrite-plan=no / identity-mismatch
claimed sequence ≠ v0.1             → rewrite-plan=no / sequence-mismatch
>1 sequence                         → rewrite-plan=no / duplicate-sequence
>1 envelope                         → rewrite-plan=no / duplicate-envelope
rewrite-plan=yes                    → applied=no / rewrite-path=no
```

## Envelope `s2c2.storage_rewrite.v1`

Query-only. Not ingested by `s2c2-opt`.

```text
schema
source-schema            s2c2.authorization.v1
identity                 (selected, object, action, license-kind)
inputs[]                 envelope, then sequence inputs, then first-seen extras
rewrite-plan             s2c2.decision.v1 subject=rewrite-plan
sequence                 KEEP,EVICT,TRANSFER,RESTORE | n/a
transformation           keep-evict-transfer-restore | n/a
applied                  no
can-run-plan             no
rewrite-path             no
```

## Reason tokens

Stage A / EA-1 still prints `authorization-tokens=none`.
7A `authorization.*` v0.1 stays frozen. 7B opens
`rewrite.*` v0.1 in
[`evidence-reason-vocab.md`](evidence-reason-vocab.md).
Emitting one is **not** `rewrite-path=yes`.

```text
decision.*            Stage-A / Decision well-formedness
authorization.* v0.1  7A policy / action / license   FROZEN
rewrite.* v0.1        7B unique plan / sequence
    ├── license-no
    ├── identity-mismatch
    ├── sequence-mismatch
    ├── duplicate-envelope
    ├── duplicate-sequence
    └── plan-closed
```

## Negative fixture matrix

| Case | Inputs | Decision |
| ---- | ------ | -------- |
| license-missing | 7A authorized=yes, license absent | plan=no `rewrite.license-no` |
| license-no | 7A license=no | plan=no `rewrite.license-no` |
| authorized-no | 7A sufficient=no + license=yes | plan=no `rewrite.license-no` |
| rewrite-plan-yes | 7A license=yes | plan=yes `rewrite.plan-closed`; path=no |
| matching-sequence | 7A license=yes + sequence v0.1 | plan=yes |
| selected-mismatch | planner selected=S1 | `rewrite.identity-mismatch` |
| object-mismatch | planner object=3 | `rewrite.identity-mismatch` |
| action-mismatch | planner action=schedule-rewrite | `rewrite.identity-mismatch` |
| license-kind-mismatch | planner license-kind=other-kind | `rewrite.identity-mismatch` |
| wrong-sequence | claimed PREFETCH | `rewrite.sequence-mismatch` |
| duplicate-sequence | two sequence inputs | `rewrite.duplicate-sequence` |
| duplicate-envelope | two 7A envelopes | `rewrite.duplicate-envelope` |
| unknown-schema | bag schema ≠ authorization.v1 | `decision.unknown-reason` |
| extras-ignored | license=yes + extra subject | plan=yes; extra ignored |
| malformed-authorized | authorized=no with license=yes | plan=no `decision.unknown-reason` |
| malformed-rewrite-license | rewrite-license `{result=yes}` only | plan=no `decision.unknown-reason` |
| source-schema-mismatch | 7A `source-schema` ≠ `s2c2.decision.v1` | plan=no `decision.unknown-reason` |
| license-identity-drift | rewrite-license.identity ≠ license-identity | plan=no `rewrite.identity-mismatch` |

## God object

```text
this host module           RewritePlanner
record_authorization.py    frozen 7A; consumed, not edited
record_sufficiency.py      frozen 6C-M; not edited
record_decision.py         frozen EA-1 usable printer
Capability schedule        frozen; do not expand
```

## Out of scope

```text
s2c2-opt IR rewrite / applySchedule / replace / erase
F_storage_schedule inhabitant
PREFETCH / PRESERVE / REMATERIALIZE sequences
can-run-plan=yes
rewrite-path=yes
changing 7A / 6C-M / EA-1 printers
frontend / extra vendors
FileCheck of microseconds
```

## Host contract

```bash
python3 runtime/record_storage_rewrite.py --print-rewrite-contract
python3 runtime/record_storage_rewrite.py --print-rewrite-matrix
```

Query-only. Host-side Decision contract, not compiler E2E.
`can-run-plan=no`. `rewrite-path=no`. `applied=no`.
