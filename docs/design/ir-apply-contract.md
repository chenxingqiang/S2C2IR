# IR Apply Contract v0.1

**Status:** design freeze for IR Apply Contract v0.1.
Semantic freeze at `038f4a1` (PR #139 — APPROVED; merge
gated). Not implemented. IR apply inhabitant stays
**CLOSED** until `PR #136 — merge`, `PR #137 — merge`,
and `PR #138 — merge` have all landed, in that order,
and Semantic Baseline v1 has passed. Does not change
frozen 6C-M / 7A / 7B evaluators. Not an
`F_storage_schedule` inhabitant. Not an expansion of
`S2C2CapabilitySchedule.cpp`. Not StableHLO. Not CIM.

This PR (#139) names the contract. It is **not** the
apply inhabitant.

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
Frozen `T` gate:
[`realization-transform.md`](realization-transform.md).

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

`rewrite-applicable` is **not** a `Decision.subject`.
v0.1 records it only as an `ApplyResult.match` field on a
later host. Do not open a new `rewrite.*` token for it.

## Consume 7B (producer contract, not re-evaluation)

This cut does **not** re-evaluate 6C-M or 7A. A later
inhabitant consumes the frozen 7B envelope.

```text
schema               = s2c2.storage_rewrite.v1
source-schema        = s2c2.authorization.v1
rewrite-plan         = well-formed Decision
                       schema=s2c2.decision.v1
                       subject=rewrite-plan
rewrite-plan.result  = yes
identity             = RewritePlanIdentity
sequence             = KEEP, EVICT, TRANSFER, RESTORE
transformation       = keep-evict-transfer-restore
```

7B producer always prints `applied=no` /
`rewrite-path=no` / `can-run-plan=no`. Apply does **not**
mutate that Decision. Success is recorded only on
`ApplyResult`.

0 / 1 / >1 rewrite envelopes:

```text
0 envelope    → no apply; missing input
1 envelope    → check identity + sequence + IR match
>1 envelope   → no apply; reuse rewrite.duplicate-envelope
```

Unknown / malformed Decision shape or `source-schema` is
`decision.unknown-reason`. Apply does **not** re-evaluate
sufficient / policy / provenance / action-match /
license-kind.

## ApplyIdentity

Same four-tuple as frozen 7B. Apply is not a new
question, so it is not a new identity.

```text
ApplyIdentity = RewritePlanIdentity
              = (selected, object, action, license-kind)
action v0.1         = storage-rewrite
license-kind v0.1   = storage-capacity-rewrite
```

```text
rewrite-plan(S0, O2, storage-rewrite, storage-capacity-rewrite)
        ≠
applied(S0, O2, storage-rewrite, storage-capacity-rewrite)
```

The latter requires the former **and** an exact IR match
**and** a successful postcondition. This cut names that
gate. It does not pass it.

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
A plan for `O2` MUST NOT act on `O3`.
A plan for `storage-rewrite` MUST NOT act on
`schedule-rewrite`.
A plan for `storage-capacity-rewrite` MUST NOT act on
another license-kind.

Disagreement is `rewrite.identity-mismatch`. That token
already exists on the frozen 7B table. Do not invent
`rewrite.apply-identity`.

## 2. IR match precondition

v0.1 matches **one** storage-pressure pattern (W0-3/2):

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

Match is exact on all of:

```text
live occupancy objects     three named stores
capacity                   2
KEEP set                   exactly two of those objects
EVICT set                  exactly the remaining one
TRANSFER                   that same EVICT object
RESTORE                    that same EVICT object
op order                   KEEP stores precede EVICT
                           EVICT precedes TRANSFER
                           TRANSFER precedes RESTORE
```

The matcher is exact. Unknown ops, extra stores, missing
stores, reordered KEEP/EVICT/TRANSFER/RESTORE, PREFETCH,
PRESERVE, or REMATERIALIZE are **not** a match.

```text
rewrite-plan=yes
        ≠
IR matches
        ≠
applied=yes
```

IR mismatch is `ApplyResult.match=no`. It is **not** a
new `Decision.subject`. It is **not** a new `rewrite.*`
token.

## 3. Apply operation

CLOSED on this cut.

When a later inhabitant opens, apply is a frozen `T`:

```text
T : P → P' ∪ {⊥}
deterministic
one sequence only
KEEP → EVICT → TRANSFER → RESTORE
not a generic rewrite engine
not a scheduler
not F_storage_schedule
not s2c2-opt owning the semantics
```

Mutation, when match holds:

```text
KEEP objects     store ops unchanged
EVICT object     store replaced by
                 evict → transfer → restore
                 in that order
other ops        unchanged
```

No partial mutation. Either the whole sequence is
written, or `T(P) = ⊥` and `P` is the result.

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
T(P) ≠ ⊥  ⇒  HB(P') = HB(P)
```

under the frozen Realization / Transform HB equality
rule ([`realization-transform.md`](realization-transform.md)),
not `HB_source ⊆ HB_impl` (that is lowering).

Also required:

```text
IsLegal(P', D, M')
identity four-tuple preserved
deterministic IR result
P' ≠ P                         # this T is not kind=id
```

Postcondition failure **rolls back**: `T(P) = ⊥`, the
input IR is the result. `applied=no`. `rewrite-path=no`.
`match` may still be `yes` (matched, then failed the
gate).

Verification is a **forced postcondition** of apply, not
an optional test. A later verification host (#140 route)
does not invent a second `T`; it re-proves this gate.

## 5. Failure semantics

| Failure | Result |
| ------- | ------ |
| rewrite-plan ≠ yes | no apply; consume 7B reasons |
| identity ≠ matched IR | no apply; `rewrite.identity-mismatch` |
| sequence ≠ v0.1 | no apply; `rewrite.sequence-mismatch` |
| >1 rewrite envelope | no apply; `rewrite.duplicate-envelope` |
| malformed 7B / source-schema | no apply; `decision.unknown-reason` |
| IR pattern mismatch | no apply; `match=no`; IR unchanged |
| HB postcondition fail | no apply; `match=yes`; IR unchanged |
| legality postcondition fail | no apply; `match=yes`; IR unchanged |
| unknown / missing input | no apply |

```text
failure = no apply
IR unchanged
rewrite-path = no
can-run-plan = no
```

No partial mutation. No best-effort remaining stores.
Do **not** invent `rewrite.apply-*` tokens.

## ApplyResult (not a Decision)

Later host, not this cut:

```text
schema           s2c2.storage_apply.v1
source-schema    s2c2.storage_rewrite.v1
identity         (selected, object, action, license-kind)
rewrite-plan     consumed Decision (unchanged)
match            yes | no
applied          no          # this cut; later: yes only on success
rewrite-path     no
can-run-plan     no
reasons[]        existing tokens only
```

```text
match=yes ∧ applied=no     allowed (postcondition fail, or this cut)
match=no  ∧ applied=yes    forbidden
applied=yes ⇒ match=yes ∧ rewrite-plan=yes ∧ HB(P')=HB(P)
```

Do **not** add `Decision.subject=rewrite-applicable`.
Do **not** reopen frozen `decision.*` / `authorization.*` /
`rewrite.*` tables to name apply failures. Reuse
`decision.unknown-reason` / `rewrite.identity-mismatch` /
`rewrite.sequence-mismatch` / `rewrite.duplicate-envelope`
where they already apply. IR mismatch and postcondition
failure live on `ApplyResult` fields, not on a new
Decision subject.

## Negative fixture matrix (design-only)

No host on this cut. A later inhabitant must cover these
cases. APPLY-0 records them as design checks.

| Case | Inputs | ApplyResult |
| ---- | ------ | ----------- |
| plan-missing | no 7B envelope | applied=no; missing input |
| plan-no | rewrite-plan=no | applied=no; 7B reasons |
| apply-yes-later | plan=yes + W0-3/2 match + HB/legal | this cut: still applied=no |
| identity-selected | plan for S0, IR is S1 | applied=no; identity-mismatch |
| identity-object | plan for O2, IR is O3 | applied=no; identity-mismatch |
| identity-action | plan action=schedule-rewrite | applied=no; identity-mismatch |
| identity-kind | license-kind ≠ storage-capacity-rewrite | applied=no; identity-mismatch |
| sequence-reorder | KEEP→RESTORE→EVICT→TRANSFER | applied=no; sequence-mismatch |
| sequence-prefetch | claimed PREFETCH | applied=no; sequence-mismatch |
| ir-extra-store | four stores, capacity=2 | match=no; applied=no |
| ir-missing-store | two stores, capacity=2 | match=no; applied=no |
| ir-unknown-op | PREFETCH in IR | match=no; applied=no |
| duplicate-envelope | two 7B envelopes | applied=no; duplicate-envelope |
| malformed-plan | rewrite-plan `{result=yes}` only | applied=no; unknown-reason |
| source-schema-mismatch | 7B source-schema ≠ authorization.v1 | applied=no; unknown-reason |
| postcondition-hb | match=yes, HB(P')≠HB(P) | applied=no; IR unchanged |
| postcondition-legal | match=yes, IsLegal fails | applied=no; IR unchanged |

Every row on this cut still has `rewrite-path=no` and
`can-run-plan=no`. The `apply-yes-later` row is the
inhabitant's happy path; this PR must not print
`applied=yes`.

## Acceptance (contract freeze)

```text
A1  ApplyIdentity = RewritePlanIdentity four-tuple
A2  consume 7B envelope; do not re-evaluate 6C-M / 7A
A3  schema=storage_rewrite.v1; source-schema=authorization.v1
A4  rewrite-plan is a well-formed Decision; result must be yes
A5  identity exact-match against matched IR realization
A6  sequence exact-match KEEP→EVICT→TRANSFER→RESTORE
A7  IR match is one pattern only (W0-3/2)
A8  rewrite-plan=yes ≠ match=yes ≠ applied=yes
A9  failure = no apply; IR unchanged; rewrite-path=no
A10 rewrite-applicable is ApplyResult.match, not a Decision
A11 no new rewrite.* / authorization.* / decision.* tokens
A12 T(P)≠⊥ ⇒ HB(P')=HB(P) and IsLegal; else T(P)=⊥
A13 no s2c2-opt / applySchedule / F_storage_schedule inhabitant
A14 this PR is the contract; inhabitant stays CLOSED
```

This page is a contract freeze, not a compiler E2E.
Do not enlarge the 17-row matrix. Do not open an apply
inhabitant or a #140 design until the three merge tokens
and Semantic Baseline v1.

## Gate vs later cuts

```text
#139 this PR     FROZEN @ 038f4a1; apply CLOSED
after merges     Semantic Baseline v1 (query stack still PASS)
later inhabitant Controlled IR Apply (one pattern)
later verify     HB + legality post-check host
later W0         storage-pressure microbenchmark
```

Those later steps are **route**, not opened PRs. Do not
treat this #139 as the inhabitant.

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

## God object

```text
this page                  Apply Contract v0.1 (design)
record_storage_rewrite.py  frozen 7B; consumed, not edited
record_authorization.py    frozen 7A; not edited
record_sufficiency.py      frozen 6C-M; not edited
record_decision.py         frozen EA-1 usable printer
Capability schedule        frozen; do not expand
s2c2-opt                   later orchestration only
```

## Host contract

None. Query-only design. No printer. No `s2c2-opt` flag.
`can-run-plan=no`. `rewrite-path=no`. `applied=no`.
