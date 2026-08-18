# Pipeline Execution Semantics

Status: **design** (not an implementation). Not a lowering.

This document defines `sched.pipeline` / `sched.stage`. It does not
rewrite Phase 2B slices 1–2. It must be approved before any pipeline
lowering.

Prerequisite: [`execution-semantics.md`](execution-semantics.md)
(Task / Event / `→HB` = TC(PO ∪ SW)). Concurrent and overlap stay as
already locked.

```text
Stage order  ≠  pipeline parallelism
```

---

## 1. Why this is a separate contract

`sched.concurrent` means **no ordering requirement** among siblings.
`sched.pipeline` looks similar in the file (a region with several
children) but means the opposite among its stages.

The hazard is to treat “pipeline” as “stages that may run in parallel,”
or to lower it like slice 2:

```text
concurrent { A, B, C }   →   N × unordered async.execute
pipeline  { S1, S2, S3 } →   N × unordered async.execute   // illegal
```

Those are different constructs. Mixing them would drop `S1 →HB S2`.

Two relations must stay distinct:

| Relation | What it orders | v0.1? |
| -------- | -------------- | ----- |
| **Stage order** | Stages of the **same** instance | yes |
| **Instance order** | Whole instance `n` vs `n+1` | no (iterations are not IR) |
| **Soft-pipe overlap** | Stages of **different** instances | no; only via future explicit events |

```text
StageOrder(S_i, S_{i+1})     =  actions(S_i)  →HB  actions(S_{i+1})
InstanceOrder(n, n+1)        =  instance n    →HB  instance n+1     (future default)
SoftPipe(n, n+1)             =  a weakening of InstanceOrder by SW   (future only)
```

`StageOrder` is the *meaning* of `sched.pipeline` today.
`SoftPipe` is **not** implied by writing stages next to each other.

---

## 2. v0.1 ontology

| Entity | Role |
| ------ | ---- |
| Pipeline | One region whose direct children are stages plus a terminator |
| Stage | A sequential region of actions, named |
| Instance | One execution of the whole stage sequence. v0.1 has **exactly one** implicit instance |

A stage is not a `Task`. It does not produce `event(Stage)` in v0.1
(the ODS ops have no token). Completion of a stage is the completion of
its body (after `sched.yield`). Completion of the pipeline is the
completion of the last stage. The parent’s next action is HB-after that
by ordinary parent PO.

Stages do not yield SSA values to each other in v0.1. Data between
stages moves through residencies (and optional events). Identity sharing
still does not move validity.

v0.1 surface: a pipeline body contains only `sched.stage` ops plus the
terminator. Nested `concurrent` / `overlap` / `pipeline` inside a stage
is out of scope (same nested-schedule deferral as concurrent).

---

## 3. Stage order (the v0.1 meaning)

For a pipeline `P = (S1, …, Sk)` of the single implicit instance:

```text
S1  →HB  S2  →HB  …  →HB  Sk
```

More precisely, for each `i`:

```text
every observable action in S_i   →HB   every observable action in S_{i+1}
```

Induced by the construct as:

```text
actions(S_i)  →PO  yield(S_i)  →HB  entry(S_{i+1})  →PO  actions(S_{i+1})
```

Inside `S_i`, actions are sequential (`→PO`), identical to a task body.

Extra `wait` / transfer events inside a stage are ordinary SW. They may
only **add** edges. They cannot remove `StageOrder`.

### 3.1 This is not “lexical order among siblings”

For `concurrent`, listing `T1` above `T2` is presentation:
`LexicalOrder(T1, T2) ∉ HB`.

For `pipeline`, the sequence of stages **is** the construct. Reordering
`S1` and `S2` in the file is a **different program**. Adjacent stages
have `StageOrder` because they are adjacent stages, not because two
unrelated ops happened to be printed that way.

```text
Concurrent sibling list   =  presentation of an unordered set
Pipeline stage list       =  the ordered construct itself
```

E6 locks the forward direction: `pack` in `S1` →HB `unpack` in `S2`.
E8 locks that the edge is directed: `unpack` in `S1` is **not**
HB-after `pack` in `S2`.

### 3.2 Pipeline completion

```text
event-less completion(P)  =  yield(S_k) has occurred
```

The parent action after `P` is HB-after every action in every stage.
Unused inner transfer tokens still do not invent sibling-style awaits
*among stages*; stages are already totally ordered by `StageOrder`.

---

## 4. What v0.1 pipeline is not

```text
Pipeline  ≠  Concurrent
Pipeline  ≠  Overlap
Pipeline  ≠  software-pipelined iterations
Pipeline  ≠  N unordered async.execute
```

| Construct | HB among children |
| --------- | ----------------- |
| `sched.concurrent` | none, unless a child waits an event |
| `sched.overlap` | none (2-way concurrent sugar) |
| `sched.pipeline` (v0.1) | `StageOrder`: `S_i →HB S_{i+1}` |

`MustExecuteConcurrently` is not the definition of concurrent.
`MayOverlapStages` is not the definition of pipeline.

A sequential inline of `S1` then `S2` then `Sk` **preserves** v0.1
pipeline HB. An unordered launch of the stages **does not**.

```text
ValidSchedules(P)  (v0.1, one instance)
    =  linear extensions of  (PO_inside_stages  ∪  StageOrder  ∪  SW)
```

With no extra SW, that order is essentially unique: the stages cannot
slide past each other.

```text
SequentialSchedule(S1; S2; …; Sk)  ∈  ValidSchedules(P)
UnorderedSchedule(S1 ∥ S2 ∥ …)     ∉  ValidSchedules(P)
```

---

## 5. Future iterations (not IR yet)

Do not add iteration ops, trip counts, or induction variables in this
slice. Record only the relations so a later lowering cannot invent them.

When an instance `n` exists:

```text
StageOrder_n :  S1(n) →HB S2(n) →HB … →HB Sk(n)
```

always remains. Overlap of `S2(n)` with `S1(n+1)` is **not** a
weakening of `StageOrder`. It is a weakening of **instance** order.

### 5.1 Default instance order (no overlap)

```text
instance n  →HB  instance n+1
```

i.e. `yield(Sk(n)) →HB entry(S1(n+1))`. No two instances are in flight.
This is ordinary loop-carried HB, not software pipelining.

```text
S1(n) ─HB─► S2(n) ─HB─► S3(n) ─HB─► S1(n+1) ─HB─► S2(n+1) ─HB─► …
```

### 5.2 Soft-pipe overlap (explicit events only)

To allow `S1(n+1)` to start before `Sk(n)` finishes, the program must
state a **synchronizes-with** edge that names which completion of
instance `n` the next instance may observe. Lexical placement of
stages does not create that edge.

```text
S1(n) ─HB─► S2(n) ─HB─► S3(n)
  │
  └── event(S1(n)) ─SW─► wait in S1(n+1)     // example only
S1(n+1) ─HB─► S2(n+1) ─HB─► S3(n+1)
```

`StageOrder` on each instance still holds. `S2(n)` and `S1(n+1)` are
unordered **only if** no HB path connects them. If they write the same
residency without such an edge, the program is undefined (ordinary
conflict / validity rules).

```text
SoftPipe  =  InstanceOrder weakened by explicit SW
          ≠  deleting StageOrder
          ≠  Concurrent(S1, S2, S3)
```

Until iteration IR exists:

```text
Do not assume overlapped pipelines.
Do not lower v0.1 pipeline as if instances were in flight.
```

---

## 6. Overlap is not a pipeline

[`execution-semantics.md`](execution-semantics.md) §6.1 is unchanged:

```text
overlap { compute } { communicate }  =  Concurrent(T_compute, T_communicate)
```

That is 2-way `NoOrderingRequirement`, plus whatever SW the regions
write. It is not `StageOrder(compute, communicate)` and not
`StageOrder(communicate, compute)`.

Phase 2A’s “communicate then compute” inline is one legal total order
under the blocking approximation, not this definition.

Do not lower `sched.pipeline` by reusing `sched.overlap` or
`sched.concurrent` rewrites.

---

## 7. Lowering consequences (do not implement here)

A later HB-preserving realization of **v0.1** pipeline may:

- inline stages in stage order (sequential body), or
- emit one `async.execute` per stage **and** make each successor
  wait the predecessor’s completion (chained SW that realizes
  `StageOrder`)

It must not:

- explode stages to sibling `async.execute` with no await
  (that is slice 2 / concurrent)
- invent instance overlap or software pipelining
- treat `sched.overlap` as a pipeline
- drop `StageOrder` because file order “looks like” concurrent siblings

Acceptance for a future lowering slice, when it exists:

```text
HB-preserving pipeline lowering
```

not “the pipeline runs in parallel.”

---

## 8. Tests

| ID | Claim | Status |
| -- | ----- | ------ |
| E6 | `S1` pack →HB `S2` unpack: defined | exists (`test/Semantics/e6.mlir`) |
| E8 | `S1` unpack, `S2` pack: undefined (edge is directed) | this PR |
| — | iteration overlap / soft-pipe | **not** written until iteration IR exists |
| — | pipeline → async | **not** this phase |

C4 (token `comm.copy` vs `comm.stream`) remains a later token-slice
regression, not a pipeline test.

---

## 9. Non-goals

- Any `sched.pipeline` / `sched.stage` → async / memref rewrite
- Iteration, trip count, or induction IR
- Conflict / race checker
- Changing Concurrent, token, or wait contracts
