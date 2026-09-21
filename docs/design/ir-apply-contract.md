# IR Apply Contract v0.1

**Status:** design/open. Not implemented. Not frozen until
this PR is `APPROVED`. IR apply stays **CLOSED** until
`PR #136 — merge`, `PR #137 — merge`, and
`PR #138 — merge` have all landed, in that order.
Does not change frozen 6C-M / 7A / 7B evaluators.
Not an `F_storage_schedule` inhabitant. Not an expansion
of `S2C2CapabilitySchedule.cpp`. Not StableHLO. Not CIM.

```text
Goal     name the only legal way a rewrite-plan may mutate IR
Not      if rewrite-plan: rewrite-path = yes
Rewrite  still closed; this page is the apply contract only
```

7B froze `Decision.subject=rewrite-plan`
([`storage-rewrite.md`](storage-rewrite.md)).
That Decision names KEEP→EVICT→TRANSFER→RESTORE and
**stops**. This page is the next door: how a later cut
may apply that named plan to IR. It does **not** apply
it. It does **not** reopen sufficient / authorized /
rewrite-license / rewrite-plan.

Product lock: [`compiler-spine.md`](compiler-spine.md).
Execution order:
[`compiler-execution-spine.md`](compiler-execution-spine.md).

## One question

```text
When rewrite-plan=yes already holds for
(selected, object, action, license-kind) and the unique
v0.1 sequence, under which exact IR match may the
compiler mutate the program, and what must remain true
afterwards?
```

```text
rewrite-plan=yes
        │
        ▼
Apply Contract v0.1
        │
        ├── Plan identity exact-match
        ├── Sequence exact-match
        ├── Target IR match
        ├── Apply (CLOSED this cut)
        └── Postcondition (HB / legality)
        │
        ▼
rewrite-path     still no
applied          still no
```

Never:

```text
if rewrite-plan:
    apply
```

Never:

```text
best-effort apply
```

Mismatch or failed postcondition is **safe no**:
`applied=no`, `rewrite-path=no`, IR unchanged.

## Five fields only

```text
1. Plan identity
2. IR match precondition
3. Apply operation
4. Postcondition
5. Failure semantics
```

```text
Plan
 │
 ├─ identity exact
 ├─ sequence exact
 ├─ target IR match
 │
 ▼
Apply
 │
 ▼
Postcondition
 ├─ HB preserved
 ├─ legality preserved
 └─ deterministic result
```

## 1. Plan identity

The plan consumed is the frozen 7B envelope
`s2c2.storage_rewrite.v1`.

```text
rewrite-plan.result     = yes
identity                = (selected, object, action, license-kind)
action v0.1             = storage-rewrite
license-kind v0.1       = storage-capacity-rewrite
sequence                = KEEP, EVICT, TRANSFER, RESTORE
transformation          = keep-evict-transfer-restore
```

The matched IR realization identity must equal that
four-tuple.

```text
plan.identity
    ==
matched IR realization identity
```

A plan for `S0` MUST NOT act on `S1`.

This cut does **not** re-evaluate 6C-M or 7A. It consumes
the frozen producer contracts.

## 2. IR match precondition

v0.1 matches **one** storage-pressure pattern:

```text
Before (example)

store A
store B
store C

capacity = 2
working-set > capacity
```

Plan:

```text
KEEP A
KEEP B
EVICT C
TRANSFER C
RESTORE C
```

Expected after a later apply (not this cut):

```text
store A
store B
evict C
transfer C
restore C
```

The matcher is exact. Unknown ops, extra stores, reordered
KEEP/EVICT/TRANSFER/RESTORE, PREFETCH, PRESERVE, or
REMATERIALIZE are **not** a match.

```text
rewrite-plan=yes
        ≠
IR matches
        ≠
applied=yes
```

`rewrite-applicable` is **not** a `Decision.subject`.
v0.1 records it only as an `ApplyResult` field on a later
host. Do not open a new `rewrite.*` token for it on this
page.

## 3. Apply operation

CLOSED on this cut.

When a later inhabitant opens, apply is:

```text
deterministic
one sequence only
KEEP → EVICT → TRANSFER → RESTORE
not a generic rewrite engine
not a scheduler
not F_storage_schedule
not s2c2-opt owning the semantics
```

`s2c2-opt` may later **orchestrate** parse / analyze /
consume / apply / verify. It does not invent the contract.

```text
S²C² semantic stack
        ↓
rewrite-plan
        ↓
controlled apply API
        ↓
s2c2-opt orchestration
```

## 4. Postcondition

After a successful apply (later inhabitant):

```text
HB_before = HB_after
```

under the frozen Realization / Transform HB equality
rule (`HB(P') = HB(P)`), not `HB_source ⊆ HB_impl`.

Also required:

```text
legality preserved
identity preserved
deterministic IR result
```

Postcondition failure **rolls back**: the input IR is the
result. `applied=no`. `rewrite-path=no`.

Verification is a **forced postcondition** of apply, not
an optional test.

## 5. Failure semantics

| Failure | Result |
| ------- | ------ |
| rewrite-plan ≠ yes | no apply |
| identity ≠ matched IR | no apply |
| sequence ≠ v0.1 | no apply |
| IR pattern mismatch | no apply |
| HB postcondition fail | no apply; IR unchanged |
| legality postcondition fail | no apply; IR unchanged |
| unknown / missing input | no apply |

```text
failure = no apply
IR unchanged
rewrite-path = no
can-run-plan = no
```

No partial mutation. No best-effort remaining stores.

## ApplyResult (not a Decision)

Later host, not this cut:

```text
schema           s2c2.storage_apply.v1
source-schema    s2c2.storage_rewrite.v1
identity         (selected, object, action, license-kind)
rewrite-plan     consumed Decision
match            yes | no
applied          no          # this cut; later: yes only on success
rewrite-path     no
can-run-plan     no
reasons[]        existing tokens only; do not invent rewrite.apply-*
```

Do **not** add `Decision.subject=rewrite-applicable`.
Do **not** reopen frozen `decision.*` / `authorization.*` /
`rewrite.*` tables to name apply failures. Reuse
`decision.unknown-reason` / `rewrite.identity-mismatch` /
`rewrite.sequence-mismatch` where they already apply.

## Gate vs later cuts

```text
this page     contract only; apply CLOSED
after merges  Semantic Baseline v1 (query stack still PASS)
#139 later    Controlled IR Apply inhabitant
#140 later    HB + legality post-check host
#141 later    storage-pressure microbenchmark
```

Those later numbers are **route**, not opened PRs.

## Out of scope

```text
IR replace / erase / applySchedule inhabitant
s2c2-opt rewrite pass
F_storage_schedule
generic rewrite engine / scheduler
Decision.subject=rewrite-applicable
new rewrite.* tokens
changing 6C-M / 7A / 7B evaluators
CUDA / CIM / StableHLO / frontend
Cost ranking / Pareto / multi-candidate search
FileCheck of microseconds
```

## Host contract

None. Query-only design. No printer. No `s2c2-opt` flag.
`can-run-plan=no`. `rewrite-path=no`. `applied=no`.
