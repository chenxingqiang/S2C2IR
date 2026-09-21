# Compiler Execution Spine

**Status:** design/open for the post-7B execution route.
Not implemented. IR apply CLOSED. Does not merge #136 /
#137 / #138. Does not change frozen evaluators.
Not StableHLO. Not CIM. Not CUDA compiler.

PR #139 is this contract/route page. It is **not** an
apply inhabitant.

```text
Goal     name how frozen query Decisions become one
         measured transformation
Not      a new Decision subject, dialect, or optimizer
Rewrite  still closed until the three merge tokens,
         Semantic Baseline v1, and a later apply inhabitant
```

Product lock: [`compiler-spine.md`](compiler-spine.md).
Apply contract: [`ir-apply-contract.md`](ir-apply-contract.md).

## Frozen query stack

```text
#136  6C-M Sufficiency     FROZEN @ a0a2a08
#137  7A Authorization     FROZEN @ 5b57666
#138  7B Rewrite Plan      FROZEN @ 3e942a8
                           bookkeeping @ fe8f510
#139  IR Apply Contract    design/open; inhabitant CLOSED
IR apply                   CLOSED
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

## Merge order (gated)

Exact tokens only: `PR #N — merge` / `合并`.
APPROVED is not merge.

```text
PR #136 — merge
        ↓
main obtains 6C-M
        ↓
PR #137 — merge
        ↓
main obtains 7A
        ↓
PR #138 — merge
        ↓
main obtains 7B Rewrite Plan
        ↓
Semantic Baseline v1
        ↓
later apply inhabitant
```

`#137` is stacked on `#136`. `#138` is stacked on `#137`.
`#139` is stacked on `#138` as the **contract**, not as
apply. Do not merge `#138` before `#137`, or `#137`
before `#136`. Do not merge `#139` as if it applied IR.

## After the three merges: Semantic Baseline v1

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

## Then: controlled IR apply

Later inhabitant, not this page and not PR #139.
Contract: [`ir-apply-contract.md`](ir-apply-contract.md).

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
IR Apply          CLOSED
 │
 ▼
HB Check          CLOSED
 │
 ▼
Legality Check    CLOSED
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
merge #136 → #137 → #138
Semantic Baseline v1
#139 this PR                 contract only
Controlled IR Apply          later inhabitant
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
merging #136 / #137 / #138
IR apply inhabitant
s2c2-opt rewrite pass
new Decision subjects
F_storage_schedule
StableHLO / CIM / CUDA compiler
frontend
FileCheck of microseconds
```
