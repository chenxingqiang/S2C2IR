# Semantic Baseline v1

**Status:** verification-only checkpoint after
`#136` / `#137` / `#138` landed on `main`.
No new semantics. Not an IR apply. Not `#139` merge.
Apply inhabitant stays **CLOSED**. This GitHub PR is
the baseline checkpoint, not a rewrite inhabitant.

```text
Goal     prove the frozen Decision stack still composes on main
Not      a new Decision subject, evaluator, or rewrite
Rewrite  still closed; applied=no; rewrite-path=no
```

Product lock: [`compiler-spine.md`](compiler-spine.md).

## Landed stack

```text
#136  6C-M Sufficiency     MERGED @ a0a2a08
#137  7A Authorization     MERGED @ 5b57666
#138  7B Rewrite Plan      MERGED @ 3e942a8
                           bookkeeping @ fe8f510
#139  IR Apply Contract    NOT MERGED; inhabitant CLOSED
Apply inhabitant           CLOSED (not this PR)
```

## Decision stack (this checkpoint)

```text
EA-1                → usable
Sufficiency         → sufficient
Authorization       → authorized
Authorization       → rewrite-license
Rewrite Planner     → rewrite-plan
Apply Contract      → specification only (#139; not on main)
```

```text
usable
sufficient
authorized
rewrite-license
rewrite-plan
```

Still:

```text
NO rewrite-path
NO applied
NO can-run-plan
NO IR mutation
NO F_storage_schedule
```

## Acceptance table

| Layer | Required result |
| ----- | --------------- |
| EA-1 | `Decision.subject=usable` only |
| 6C-M | 16-case matrix passes |
| 7A | 20-case matrix passes |
| 7B | 18-case matrix passes |
| legacy RCE / XID | frozen compose hosts pass |
| Apply contract | spec only; not merged |
| IR mutation | none |
| `F_storage_schedule` | none |
| `rewrite-path` | `no` |
| `can-run-plan` | `no` |
| `applied` | `no` |

## Provenance

Replay frozen producers. Do not re-evaluate.

| Subject | Producer | Envelope | Identity |
| ------- | -------- | -------- | -------- |
| usable | `record_decision.py` | `s2c2.decision.v1` | `(selected, object)` EA-1 |
| sufficient | `record_sufficiency.py` | `s2c2.sufficiency.v1` source=`s2c2.decision.v1` | `(selected, object)` |
| authorized | `record_authorization.py` | `s2c2.authorization.v1` source=`s2c2.decision.v1` | `(selected, object, action)` |
| rewrite-license | same 7A envelope | same | `(selected, object, action, license-kind)` |
| rewrite-plan | `record_storage_rewrite.py` | `s2c2.storage_rewrite.v1` source=`s2c2.authorization.v1` | same four-tuple |

v0.1 action is `storage-rewrite`. v0.1 license-kind is
`storage-capacity-rewrite`.

This checkpoint classifies later failures:

```text
semantic regression     Decision stack / producer contract
execution regression    later apply / HB / legality / measure
```

## PASS iff

```text
EA-1        = PASS   subject=usable, not sufficient
6C-M 16/16  = PASS   suf._validate(); usable∧applicable ≠ sufficient
7A 20/20    = PASS   auth._validate(); policy-missing ⇒ authorized=no
                     license-missing ⇒ rewrite-license=no
7B 18/18    = PASS   rew._validate(); plan=yes still applied=no
legacy      = PASS   RCE + XID
provenance  = consistent
no new Decision.subject
no IR mutation
no apply inhabitant
record_storage_apply.py absent
rewrite-path=no
can-run-plan=no
applied=no
F_storage_schedule absent
```

```text
Semantic Baseline v1 = PASS
```

only when every line above holds. Then, and only then:

```text
PR #140 — APPROVED
        ↓
freeze baseline
        ↓
PR #139 — merge
        ↓
open Controlled IR Apply
```

## Out of scope

```text
merging #139
opening an IR apply inhabitant
new Decision.subject
new rewrite.* / authorization.* tokens
F_storage_schedule
s2c2-opt rewrite
StableHLO / CUDA / CIM / frontend
FileCheck of microseconds
```

## Host contract

```bash
python3 runtime/record_semantic_baseline.py --print-semantic-baseline-contract
python3 runtime/record_semantic_baseline.py --print-semantic-baseline-summary
```

Query-only. Replays frozen `_validate` / EA-1 contract.
`can-run-plan=no`. `rewrite-path=no`. `applied=no`.
