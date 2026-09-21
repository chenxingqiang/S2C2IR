# 6C-M Sufficiency Decision

**Status:** design freeze for `Decision.subject=sufficient`.
Not authorization. Not a rewrite. Not 6C-I `sufficient=no`.
Not an expansion of `S2C2CapabilitySchedule.cpp`.
Not `F_storage_schedule`.

```text
Goal     evaluate sufficiency as a named Decision subject
Not      usable ∧ applicable, rewrite-license, or can-run-plan
Rewrite  still only from a later authorization cut (7A)
```

Stage A froze Decision *shape* and emits
`Decision.subject=usable` only
([`evidence-decision.md`](evidence-decision.md)).
6C-J/K/L froze independent occupancy kinds. This cut
opens the **first** `Decision.subject=sufficient` record
via a SufficiencyEvaluator. It does **not** fold those
kinds into a printer AND inside `record_capacity.py`.

Product lock: [`compiler-spine.md`](compiler-spine.md).

## Why not a boolean AND

```text
usable = yes
applicable = yes
        ≠
sufficient = yes
```

```text
usable = yes
dest-invalidation = yes
        ≠
sufficient = yes
```

Those implications are the parked 6C-L / EA-1 lock. They
stay true for every host that is not this evaluator.
6C-I still prints `sufficient=no` on the license
predicate. EA-1 / `record_decision.py` still do not emit
`Decision.subject=sufficient`.

A lone

```text
sufficient = usable ∧ dest-invalidation ∧ …
```

inside the capacity query printer would hide *which*
conjunct failed and would smuggle authorization later.
6C-M names the question instead.

## SufficiencyEvaluator

```text
Evidence / Predicate results
      │
      ├── usable
      ├── restore-ordering
      ├── dest-invalidation
      ├── capacity-legal
      └── other named results (ignored)
                    │
                    ↓
             SufficiencyEvaluator
                    │
             ┌──────┴──────┐
             ↓             ↓
          sufficient    insufficient
```

Required inputs are independent named predicate results,
not EvidenceRecord bool fields:

```text
REQUIRED = (usable, restore-ordering, dest-invalidation, capacity-legal)
```

`usable` already means `source-data ∧ restore-ordering`.
`restore-ordering` is still a required *input* of the
evaluator. The evaluator does not re-derive `usable`.
Inconsistent bags (usable=yes, restore-ordering=no) are
insufficient because a required input is not `yes`.

`applicable` is **not** required. Extra subjects
(`applicable`, `authorized`, …) are ignored.

## Decision

```text
Decision
  schema     s2c2.decision.v1
  subject    sufficient
  result     yes | no
  reasons[]  typed tokens
```

```text
yes  iff every REQUIRED input is present and result=yes
no   otherwise (missing, no, n/a, unknown, duplicate)
```

Unknown / missing → safe no. The evaluator does **not**
emit `Decision.result=n/a`. That keeps Stage A's
unknown → no rule for this subject.

On `result=yes`:

```text
reasons = decision.sufficient-closed
```

On `result=no`, reasons are collected in REQUIRED order:

| Input | Token |
| ----- | ----- |
| missing | `predicate.missing-input` (once, after specific tokens) |
| `no` | `predicate.<subject>-no` |
| `n/a` | `predicate.<subject>-n/a` |
| unknown result | `decision.unknown-reason` |
| duplicate subject | `decision.duplicate-identity` (stops) |

## Envelope `s2c2.sufficiency.v1`

Query-only. Not ingested by `s2c2-opt`.

```text
schema
source-schema           s2c2.decision.v1
identity                (selected, object)
inputs[]                {subject, result} in REQUIRED order, then extras
decision                s2c2.decision.v1 subject=sufficient
sufficiency-evaluation  evaluated
can-run-plan            no
authorization           n/a
rewrite-license         no
rewrite-path            no
```

```text
sufficiency-evaluation = evaluated   ≠  can-run-plan=yes
Decision.result=yes                  ≠  rewrite-license=yes
Decision.result=yes                  ≠  authorized
```

## Forced distinctions

```text
Decision.subject=sufficient  ≠  Decision.subject=usable
Decision.subject=sufficient  ≠  Decision.subject=applicable
Decision.subject=sufficient  ≠  Decision.subject=authorized
sufficient                   ≠  authorized
sufficient                   ≠  rewrite-license
sufficient                   ≠  can-run-plan
6C-M evaluator               ≠  6C-I license predicate
6C-M evaluator               ≠  EA-1 usable printer
```

Future subjects stay independent:

```text
usable | applicable | sufficient | authorized
```

## Negative fixture matrix

| Case | Inputs | Decision |
| ---- | ------ | -------- |
| all-required-yes | four REQUIRED = yes | `result=yes` `decision.sufficient-closed`; still `rewrite-license=no` |
| dest-inv-historic | usable + restore-ordering + dest-invalidation = yes; capacity-legal missing | `no` `predicate.missing-input` |
| usable-and-applicable-ne-sufficient | usable=yes, applicable=yes, others missing | `no` `predicate.missing-input` |
| usable-no | usable=no, others yes | `no` `predicate.usable-no` |
| restore-ordering-no | restore-ordering=no, others yes | `no` `predicate.restore-ordering-no` |
| dest-invalidation-no | dest-invalidation=no, others yes | `no` `predicate.dest-invalidation-no` |
| capacity-legal-no | capacity-legal=no, others yes | `no` `predicate.capacity-legal-no` |
| dest-invalidation-n/a | dest-invalidation=n/a, others yes | `no` `predicate.dest-invalidation-n/a` |
| missing-usable | usable absent, others yes | `no` `predicate.missing-input` |
| ignore-applicable-extra | four REQUIRED = yes + applicable=no | `yes`; applicable is not a conjunct |
| duplicate-usable | two usable inputs | `no` `decision.duplicate-identity` |
| ignore-authorized-extra | four REQUIRED = yes + authorized=yes | `yes`; `authorization=n/a`; no `authorization.*` |

```text
usable=yes ∧ dest-invalidation=yes
        ≠
sufficient=yes          unless capacity-legal is also yes
```

The historic dest-invalidation fixture remains
insufficient until `capacity-legal` is present and yes.

## God object

```text
this host module           SufficiencyEvaluator
record_decision.py         frozen EA-1 usable printer
record_capacity.py         frozen 6C-I sufficient=no
Capability schedule        frozen pair-license host; do not expand
6B Evidence DB             frozen measured identity E
```

## Out of scope

```text
authorization.* tokens
rewrite-license=yes
rewrite-path / replace / erase
can-run-plan=yes
Decision.subject=authorized
changing EA-1 / 6C-I printers
F_storage_schedule inhabitant
new occupancy kinds
new capability kinds
generic schema validator
frontend / extra vendors
FileCheck of microseconds
```

## Host contract

```bash
python3 runtime/record_sufficiency.py --print-sufficiency-contract
python3 runtime/record_sufficiency.py --print-sufficiency-matrix
```

Query-only. `Decision.subject=sufficient`.
`sufficiency-evaluation=evaluated`. `can-run-plan=no`.
`authorization=n/a`. `rewrite-license=no`. `rewrite-path=no`.
