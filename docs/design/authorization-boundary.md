# 7A Authorization Boundary

**Status:** design/open for `Decision.subject=authorized`
and `Decision.subject=rewrite-license`. Not frozen until
`PR #137 — APPROVED`.
Not a rewrite. Not 7B. Not an `F_storage_schedule` inhabitant.
Not an expansion of `S2C2CapabilitySchedule.cpp`.
Does not change the frozen 6C-M evaluator.

```text
Goal     decide whether a named action is permitted
Not      if sufficient: authorized = yes
Rewrite  still closed; rewrite-license=yes does not transform IR
```

6C-M froze `Decision.subject=sufficient` over
`(selected, object)`
([`storage-capacity-sufficient.md`](storage-capacity-sufficient.md)).
This cut is the second door. It consumes that Decision. It
does **not** re-evaluate usable / restore-ordering /
dest-invalidation / capacity-legal.

Product lock: [`compiler-spine.md`](compiler-spine.md).

## One question

```text
When a realization is already sufficient=yes, under which
independent policy / evidence / action identity may the
compiler adopt a behaviour-changing action?
```

```text
sufficient
    │
    ▼
Authorization Evaluator
    │
    ├── Policy v0.1
    ├── Evidence provenance
    ├── Action identity
    ├── Scope (selected, object, action)
    └── Provenance
    │
    ▼
authorized
    │
    ▼
rewrite-license
```

## Three subjects stay distinct

```text
sufficient        Can this realization satisfy required
                  semantic / resource conditions?
authorized        Is this action permitted under the
                  applicable policy / evidence?
rewrite-license   Does this authorization explicitly license
                  this class of transformation?
```

```text
sufficient        ≠  authorized
authorized        ≠  rewrite-license
sufficient=yes    ≠  rewrite-license=yes
authorized=yes    ≠  rewrite-path=yes
```

Never:

```text
if sufficient:
    authorized = yes
```

Never:

```text
if authorized:
    rewrite-license = yes
```

## AuthorizationIdentity

6C-M identity is `(selected, object)`. Authorization is
not the same question, so it is not the same identity.

```text
AuthorizationIdentity = (selected, object, action)
```

v0.1 names one action and does **not** implement it:

```text
action = storage-rewrite
```

```text
sufficient(S0, O2)
        ≠
authorized(S0, O2, storage-rewrite)
```

The latter requires:

```text
authorization(
    selected = S0,
    object   = O2,
    action   = storage-rewrite,
    policy   = authorization-policy-v0.1,
    evidence provenance = known
)
```

`rewrite-license` has a fourth component:

```text
RewriteLicenseIdentity = (selected, object, action, license-kind)
license-kind v0.1      = storage-capacity-rewrite
```

Later `schedule-rewrite` / `device-placement` get their
own action identities. They must not share a bare
`authorized=yes`.

## Policy v0.1

Minimal. Not a generic optimizer policy.

```text
required  sufficient.result = yes
required  policy-match      = authorization-policy-v0.1
required  provenance        = known
required  action            = exact-match of evaluator action
```

```text
all four yes, in-scope, unique
        ↓
authorized = yes
```

otherwise `authorized = no`. Unknown / missing → safe no.

## SufficiencyEvaluator vs AuthorizationEvaluator

```text
6C-M scope     (selected, object)
7A   scope     (selected, object, action)
```

The sufficient input must match `(selected, object)`.
The other required inputs must match
`(selected, object, action)`.

For `action-match`:

```text
identity.action   = target action being evaluated
record.action     = claimed action
```

A claimed mismatch with an in-scope identity is
`authorization.action-mismatch`, not
`decision.identity-mismatch`.

`rewrite-license` is a **license input**, not an ignored
extra:

```text
0 license     → rewrite-license=no / missing
1 license     → evaluate scope + result
>1 license    → decision.duplicate-identity
```

First-seen license must not win. Other extra subjects,
including duplicate extras, are ignored. Duplicate
REQUIRED subjects are safe no.

## Decisions

```text
Decision
  schema     s2c2.decision.v1
  subject    authorized | rewrite-license
  result     yes | no
  reasons[]  typed tokens
```

The evaluator does **not** emit `result=n/a`.

On `authorized=yes`:

```text
reasons = decision.authorized-closed
```

On `rewrite-license=yes` (only if `authorized=yes` **and**
an explicit in-scope license input is yes with
`license-kind=storage-capacity-rewrite`):

```text
reasons = decision.rewrite-license-closed
```

Guardrails:

```text
sufficient=yes + policy missing     → authorized=no
authorized=yes + license missing    → rewrite-license=no
authorized=no  + license=yes        → rewrite-license=no
>1 license                          → rewrite-license=no / duplicate-identity
license-kind ≠ v0.1                 → rewrite-license=no / identity-mismatch
```

`rewrite-license=yes` is a query Decision. It does **not**
open `applySchedule`, replace, erase, or `s2c2-opt` rewrite.
`rewrite-path` stays `no`. `can-run-plan` stays `no`.
`transformation` stays `n/a`.

## Envelope `s2c2.authorization.v1`

Query-only. Not ingested by `s2c2-opt`.

```text
schema
identity                 (selected, object, action)
inputs[]                 REQUIRED order, then license inputs, then first-seen extras
authorized               s2c2.decision.v1 subject=authorized
rewrite-license          s2c2.decision.v1 subject=rewrite-license
license-identity         (selected, object, action, license-kind) | n/a
can-run-plan             no
rewrite-path             no
transformation           n/a
```

## Reason tokens

Stage A vocabulary freeze remains: EA-1 /
`record_decision.py` still prints `authorization-tokens=none`.
7A opens `authorization.*` v0.1 in
[`evidence-reason-vocab.md`](evidence-reason-vocab.md).
This host may emit those tokens. Emitting one is **not**
a rewrite.

## Negative fixture matrix

| Case | Inputs | Decisions |
| ---- | ------ | --------- |
| sufficient-no | sufficient=no, other REQUIRED yes | authorized=no; license=no |
| sufficient-yes-policy-missing | sufficient=yes, policy absent | authorized=no |
| wrong-policy | policy name ≠ v0.1 | authorized=no |
| unknown-policy | policy result=unknown | authorized=no |
| action-mismatch | identity.action=storage-rewrite, claimed=schedule-rewrite | authorized=no `action-mismatch` |
| selected-mismatch | sufficient selected=S1 | identity-mismatch |
| object-mismatch | sufficient object=3 | identity-mismatch |
| provenance-missing | provenance absent | authorized=no missing-input |
| provenance-unknown | provenance=unknown | authorized=no |
| duplicate-identity | two sufficient inputs | duplicate-identity |
| authorized-yes-license-missing | four REQUIRED yes, license absent | authorized=yes; license=no |
| rewrite-license-no | four yes, explicit license=no | authorized=yes; license=no |
| rewrite-license-yes | four yes, explicit license=yes | authorized=yes; license=yes; path=no |
| rewrite-license-kind-mismatch | four yes, license-kind=other-kind | license=no identity-mismatch |
| duplicate-license | four yes, two license inputs | authorized=yes; license=duplicate-identity |
| missing-action-match | action-match absent | authorized=no |
| sufficient-n/a | sufficient=n/a | authorized=no |
| shuffled-required | REQUIRED reversed | canonical inputs order |
| consume-6c-m-yes | 6C-M evaluator output | authorized=yes; license=no |
| license-yes-but-not-authorized | sufficient=no, license=yes | authorized=no; license=no |

## God object

```text
this host module           AuthorizationEvaluator
record_sufficiency.py      frozen 6C-M; consumed, not edited
record_decision.py         frozen EA-1 usable printer
record_capacity.py         frozen 6C-I sufficient=no
Capability schedule        frozen; do not expand
```

## Out of scope

```text
7B IR rewrite / applySchedule / replace / erase
F_storage_schedule inhabitant
can-run-plan=yes
generic optimizer / scheduler
new actions beyond storage-rewrite
changing 6C-M / EA-1 / 6C-I printers
frontend / extra vendors
FileCheck of microseconds
```

## Host contract

```bash
python3 runtime/record_authorization.py --print-authorization-contract
python3 runtime/record_authorization.py --print-authorization-matrix
```

Query-only. Host-side Decision contract, not compiler E2E.
`can-run-plan=no`. `rewrite-path=no`. `transformation=n/a`.
