# Compiler Execution Spine

**Status:** IR Apply Contract frozen @ `038f4a1`.
`#136` / `#137` / `#138` / `#140` / `#139` are on `main`.
Semantic Baseline v1 PASS is a prerequisite, not apply
authorization. W0-3/2 inhabitant v0 is the host in
[`ir-apply-inhabitant.md`](ir-apply-inhabitant.md).
It does not change frozen 6C-M / 7A / 7B evaluators.
Not StableHLO. Not CIM. Not CUDA compiler.
`can-run-plan` stays no.

`#139` is merged @ `2821de8`. The W0-3/2 host exists.
Semantic Baseline replay does not execute that host.

```text
Goal     name how frozen query Decisions become one
         measured transformation
Not      a new Decision subject, dialect, or optimizer
Rewrite  host is W0-3/2 only; Baseline replay does not apply
```

Product lock: [`compiler-spine.md`](compiler-spine.md).
Apply contract: [`ir-apply-contract.md`](ir-apply-contract.md).

## Frozen query stack

```text
#136  6C-M Sufficiency     MERGED @ a0a2a08
#137  7A Authorization     MERGED @ 5b57666
#138  7B Rewrite Plan      MERGED @ 3e942a8
#140  Semantic Baseline v1 MERGED @ b62bae4  PASS
#139  IR Apply Contract    MERGED @ 2821de8 / freeze 038f4a1
W0-3/2 inhabitant v0       host; not Enum_F; can-run-plan=no
```

```text
sufficient
  ≠ authorized
  ≠ rewrite-license
  ≠ rewrite-plan
  ≠ rewrite-path
```

7B STOP:

```text
rewrite-plan=yes
  applied=no
  rewrite-path=no
  can-run-plan=no
  transformation=keep-evict-transfer-restore
```

`rewrite-sequence.result` is non-authoritative. Do not
reopen 7B to require `result=yes`.

## Merge order (landed)

`#136` / `#137` / `#138` / `#140` / `#139` are on `main`.
`#139` merged @ `2821de8`.

```text
#136 / #137 / #138 MERGED
        ↓
Semantic Baseline v1 PASS   (#140 MERGED)
        ↓
#139 Apply Contract         MERGED @ 2821de8
        ↓
W0-3/2 inhabitant v0       host; can-run-plan=no
```

`#139` merged the contract. The host is a separate cut.
Baseline PASS ≠ `can-run-plan`.

## Semantic Baseline v1 (landed)

Replay is complete on `main`. This is a prerequisite.

Do **not** write apply immediately after merge.

First replay the frozen query hosts:

```text
EA-1     PASS     Decision.subject=usable only
6C-M     PASS     Decision.subject=sufficient
7A       PASS     authorized / rewrite-license
7B       PASS     rewrite-plan
legacy   PASS
```

```text
Decision Stack

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
```

If a later apply fails, this baseline answers whether
execution broke or the semantic stack broke.

## W0-3/2 inhabitant host

The host is
[`ir-apply-inhabitant.md`](ir-apply-inhabitant.md).
`#139` remains the contract
([`ir-apply-contract.md`](ir-apply-contract.md)).
Semantic Baseline replay does not execute the host.

The host constructs `P'` then commits. It does not mutate
`P` in place and roll back. `can-run-plan` stays no.

```text
rewrite-plan=yes
        ↓
validate 7A/7B producer contracts
        ↓
identity exact-match
        ↓
sequence exact-match
        ↓
target IR match
        ↓
apply KEEP→EVICT→TRANSFER→RESTORE
        ↓
HB / legality postcondition
        ↓
rewrite-path=yes only on success
```

One pattern only (W0-3/2). No generic rewrite engine. No
scheduler. No `F_storage_schedule`. Failure = no apply,
IR unchanged.

`rewrite-applicable` stays an `ApplyResult.match` field,
not a new `Decision.subject`.

`s2c2-opt` is later **orchestration**:

```text
parse → analyze → candidate → legality → sufficiency
     → authorization → rewrite-plan → apply → verify
```

It does not own those semantics.

## Execution spine (target, not this cut)

```text
IR
 │
 ▼
Evidence
 │
 ▼
Predicate
 │
 ▼
Sufficiency
 │
 ▼
Authorization
 │
 ▼
Rewrite License
 │
 ▼
Rewrite Plan
 │
 ▼
Plan / IR Match
 │
 ▼
IR Apply          host v0; baseline does not execute it
 │
 ▼
HB Check          host v0
 │
 ▼
Legality Check    host v0; external witness
 │
 ▼
Lowering          later
 │
 ▼
Runtime           later
 │
 ▼
Measurement       later
```

KPI after the inhabitant, not now:

```text
one authorized plan
  → one actual IR transformation
  → HB / legality verified
  → measured
```

## Suggested later route (not opened)

```text
#136 / #137 / #138 MERGED
#140 Semantic Baseline v1    MERGED PASS
#139 IR Apply Contract        MERGED @ 2821de8
W0-3/2 inhabitant            host present; baseline does not execute it
Execution Verification       later (HB + legality)
W0 storage-pressure bench    later
Cost / measurement           later; legal+authorized only
CUDA realization             later
multi-candidate Search       later
StableHLO frontend           later
CIM capability adapter       later
```

Workload order: storage-pressure microbenchmark (W0-3/2),
then a pipeline+communication witness, then GPU
measurement via CPU / interpreter stand-in first.
Not Llama-full. Not StableHLO first.

Cost ranks only after legality, sufficiency, and
authorization. Never `Cost → Select → check legality`.

First apply is one plan / one rewrite. N plans, then
Pareto, come after that closed loop.

## Out of scope (this page)

```text
executing Apply inside the baseline replay
s2c2-opt rewrite pass
new Decision subjects
F_storage_schedule
StableHLO / CIM / CUDA compiler
frontend
FileCheck of microseconds
```
