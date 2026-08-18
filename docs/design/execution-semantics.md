# S²C² Execution Semantics

Status: **design**. Task / Event / Concurrent are approved (Phase 2B
slices 1–2 realize them). Pipeline is specified in
[`pipeline-semantics.md`](pipeline-semantics.md); do not lower it yet.

This document defines the execution constraint layer of S²C². It does not
describe a compiler, a runtime, or a target.

```text
S²C²  =  Storage + Compute + Communication + Execution Semantics
```

Storage, compute, and communication say *what* exists, *what* is computed,
and *how* data moves. **Schedule is not a fourth data dialect.** It is the
layer that constrains *when* those effects may become visible to each other.

```text
             Storage          Compute         Communication
                 │                │                  │
                 └────────────────┼──────────────────┘
                                  ▼
                         Execution Semantics
                         (Task / Event / HB)
```

Prerequisite contracts (already locked):

- [Phase 1.5](phase1.5-semantic-normalization.md): object ≠ residency;
  lightweight validity; generic events; `NoOrderingRequirement`
- [Phase 2A](phase2a-sequential-lowering.md): sequential / blocking
  *realization*, not this definition

Non-goals: code generation, target runtimes, frontends, hardware capability
models. Those may *implement* this relation. They must not *redefine* it.

---

## 1. Ontology

| Entity | Role |
| ------ | ---- |
| Logical object | Identity of a datum. No allocation, no contents |
| Residency | A placed replica of an object (or an anonymous scratch buffer) |
| Validity | Predicate on a residency: contents are defined |
| Value | An SSA handle (object, residency, tensor, event) |
| Action | An atomic effect: allocate, pack, compute, transfer, wait, yield |
| Task | A sequential region of actions plus one completion event |
| Event | A completion witness produced by a task or a transfer |
| Schedule | A set of tasks plus HB edges among them |

Three independent facts about data:

```text
Object identity  ≠  Residency  ≠  Validity
```

- Two residencies may share an object and still have different validity.
- `materialize` creates a residency; it does **not** make it valid.
- A transfer / copy / stream / pack makes the destination valid, at
  completion.

Validity is a predicate, not a `valid/stale/dirty/inflight` state machine.

---

## 2. Events

An **event** `e` is a completion witness. It is not owned by communication.

| Producer | What `e` witnesses |
| -------- | ------------------ |
| Task | The task region has completed; yielded values are available |
| Transfer / copy / stream | The destination residency is **valid** |

Write `event(X)` for the completion event of action or task `X`.

An event has no payload other than “this producer finished.” Validity of a
destination is a *consequence* of a transfer event, not a field stored in
the event.

`wait` and `barrier` consume events. They do not produce events.

---

## 3. Happens-before

The fundamental relation is **happens-before**:

```text
A  →HB  B
```

Meaning: the effects of `A` are complete before `B` may observe them.

`→HB` is the irreflexive transitive closure of two primitive edges:

1. **Program order (PO)** — inside a single task, actions are sequential.
   If action `a` is textually before action `b` in the same task body,
   then `a →PO b` and therefore `a →HB b`.
2. **Synchronizes-with (SW)** — an event producer synchronizes with each
   `wait` / `barrier` that consumes that event:
   `producer(e) →SW wait(e)`, hence `producer(e) →HB wait(e)`.

```text
→HB  =  transitive closure of ( →PO  ∪  →SW )
```

HB is defined over **observable actions** (allocate, pack, compute,
transfer/copy/stream, wait, yield, and the other leaf effects). Task and
Event are not themselves points in the order: a task or event edge
**induces** HB between the corresponding action regions (the actions in
the producer region, and the wait / continuation that observe the event).

So `event(T1) →HB event(T2)` is not a primitive. The induced fact is
`actions(T1) →HB wait(event(T1)) →HB continuation`.

Consequences:

- HB is a strict partial order on actions (irreflexive, transitive).
- If `A →HB B` and `B` reads a residency that `A` writes, the read is
  defined (provided `A` established validity).
- If neither `A →HB B` nor `B →HB A`, the two actions are **unordered**.
  Unordered writes to the same residency, or a read unordered with a write
  of that residency, are undefined.

### 3.1 What is *not* HB

**Textual order among sibling tasks in a concurrent region is not PO and
not SW.** It is presentation.

```text
Semantic dependence  =  PO (intra-task)  ∪  Event (SW)

Lexical order of concurrent siblings  ∉  HB
```

If task `A` writes residency `W` and task `B` reads `W`, the program must
establish

```text
A  --event(A)-->  wait in B  →  B's read
```

that is `A →HB B`. Listing `A` above `B` in the file does **not** create
that edge.

Phase 2A sequentialize may use sibling IR order as one *legal total
order* after it has erased waits (a blocking realization). That is not
part of this definition.

---

## 4. Task

A task `T` is a sequential region.

```text
Task T
  consumes   : values, and optionally events (via wait)
  produces   : values (via yield), and exactly one completion event
  body       : a PO-ordered sequence of actions
```

Rules:

1. The body is sequential: adjacent actions are related by `→PO`.
2. `T` produces `event(T)` when the body has completed (after the yield).
3. Yielded values of `T` become available only after `event(T)`.
   Any use of those values outside `T` must be HB-after `event(T)`
   (typically because the parent region is sequential, or because a
   consumer waits `event(T)`).
4. A wait inside `T` is an action in `T`'s PO. The continuation of `T`
   after the wait is HB-after the waited producers.

A task may contain storage, compute, or communication actions. There is
no “compute task” vs “comm task” in the semantics — only tasks.

---

## 5. Wait

```text
wait({e1, …, en})
```

establishes, for each `i`:

```text
producer(ei)  →SW  wait  →PO  (continuation)
```

hence

```text
producer(ei)  →HB  continuation
```

`barrier({e1, …, en})` is the same relation (a wait with an optional empty
set: empty barrier is a no-op).

Wait does **not** by itself copy data or allocate. It only adds HB.

---

## 6. Concurrent

```text
Concurrent(T1, …, Tn)  =  NoOrderingRequirement(T1, …, Tn)
```

`Concurrent` inserts **no** HB edges among `{T1, …, Tn}`.

Children may still be ordered if they themselves create SW edges (a child
waits another child's event).

```text
ValidSchedules(C)  =  { total orders of C's actions that respect →HB }
```

```text
SequentialSchedule  ∈  ValidSchedules
```

because a linear extension of a partial order is always a valid schedule.
`MustExecuteConcurrently` is **not** the definition. Parallel execution
is permitted, not required.

v0.1 surface (already enforced): a concurrent region contains only tasks
plus a terminator. Nested structured schedule is out of scope until this
document is extended.

### 6.1 Overlap

`overlap { compute } { communicate }` is **2-way sugar** for

```text
Concurrent(T_compute, T_communicate)
```

It adds no extra HB. A wait inside the compute region on a communicate
event is ordinary SW.

---

## 7. Transfer

A **transfer action** is `transfer`, `copy`, or `stream` that writes a
destination residency `d` from a source residency `s`.

```text
Transfer(s → d)
  requires   : Valid(s) at the start of the action
  allocates  : a new residency d, if the action is `transfer`
  produces   : event(Transfer)
  establishes: Valid(d)  at  event(Transfer)
```

```text
event(Transfer)  ⇒  Valid(d)
```

Anyone who waits `event(Transfer)` is HB-after that validity.

`pack` into `d` is a synchronous write: `Valid(d)` holds at the pack
action itself (no event unless a later revision adds one).

`materialize` / `alloc`:

```text
Exists(residency) ∧ contents unspecified
```

`unpack` / compute that reads a residency `r` is defined only if some
HB-prior action established `Valid(r)`.

Two residencies of the same object are **not** automatically coherent.
Identity sharing does not move validity. Only a transfer/copy/stream/pack
does.

---

## 8. Pipeline

Full contract: [`pipeline-semantics.md`](pipeline-semantics.md).

A pipeline is an ordered sequence of stages `S1, …, Sk` of **one**
implicit instance (v0.1: stages only; iterations are not IR).

```text
Stage order  ≠  pipeline parallelism
```

Formal relations (v0.1 uses only `StageOrder` on the implicit instance):

```text
StageOrder(S_i, S_{i+1})  ⇒  actions(S_i) →HB actions(S_{i+1})

StageOrder_n :  S1(n) →HB S2(n) →HB … →HB Sk(n)

InstanceOrder(n, n+1)  (future default, not IR):
    instance n →HB instance n+1
    i.e. yield(Sk(n)) →HB entry(S1(n+1))
```

Each stage is a sequential region (PO inside the stage). `StageOrder`
is the meaning of the construct, not `NoOrderingRequirement`.

```text
actions(S_i)  →PO  yield(S_i)  →HB  entry(S_{i+1})  →PO  actions(S_{i+1})
```

Reordering stages is a different program. That is the opposite of
concurrent siblings, whose lexical list is presentation.

`StageOrder` **induces** HB (`yield(S_i) →HB entry(S_{i+1})`). It is
not a second memory model: those edges enter the same `→HB` already
defined as the transitive closure of primitive edges. Extra SW may
only add edges; it cannot delete `StageOrder`.

Future software pipelining is **not** “add SW on top of InstanceOrder”
(SW only adds edges). It is a recorded future issue: relax/replace the
default `InstanceOrder`, then add the required SW. That does not delete
`StageOrder_n`. Until iteration IR exists, do not assume overlapped
pipelines.

`sched.overlap` remains 2-way concurrent sugar (§6.1), not a pipeline.

Do not lower `sched.pipeline` as `N ×` unordered `async.execute`.

---

## 9. Reads, writes, undefined behavior

Classify actions on a residency `r`:

| Kind | Actions |
| ---- | ------- |
| Allocate | `materialize`, `alloc`, `transfer` (dest) |
| Write (establishes Valid) | `pack`, `transfer`/`copy`/`stream` (dest, at event) |
| Read (requires Valid) | `unpack`, `copy`/`stream`/`transfer` (source), compute after unpack |

A read of `r` is **defined** iff there exists a write `W` of `r` such that
`W →HB read` and no other write `W'` of `r` is unordered with the read.

Otherwise the read is **undefined**. The IR does not have to diagnose
undefined programs in v0.1; lowering may produce arbitrary contents.

```text
Semantic validity  ≠  static verifiability
```

A program may be semantically defined without the current checker being
able to prove it (`Unknown`). A checker may `MustProve` definedness
(reject `Unknown`), `MayAssume` it, or leave it `Unknown`. v0.1
`--check-s2c2-execution` is a `MustProve` test oracle for E1–E8, not a
completeness claim about all well-defined programs.

Concurrent writes of the same residency with no HB between them are
undefined.

### Future: Conflict / Race Analysis (not v0.1)

`--check-s2c2-execution` currently implements only the first conjunct:

```text
Defined(R)  ⇐  ∃ W.  W →HB R
```

The full contract is:

```text
Defined(R)  ⇔  ∃ W. W →HB R
            ∧  ¬∃ W'. Conflict(W', R) ∧ ¬(W' →HB R)
```

An unordered conflicting write must make the program undefined. That is a
separate **Conflict / Race Semantics** checker, not part of the E1–E8
oracle. Do not fold a race detector into `--check-s2c2-execution` until
that document exists.

---

## 10. Worked examples

### 10.1 Defined: event carries validity

```text
w        = object
w_ssd    = materialize w          // Exists, not Valid
w_hbm    = materialize w          // Exists, not Valid
// assume w_ssd became Valid by a prior pack (same task PO)
e        = stream(w_ssd → w_hbm)
wait e
y        = compute(unpack w_hbm)
```

```text
stream  →SW  wait  →PO  compute
```

`Valid(w_hbm)` at `event(stream)`, so the compute is defined.

### 10.2 Undefined: materialize is not a fill

```text
w_hbm = materialize w
y     = compute(unpack w_hbm)    // no prior write, no event
```

No `Valid(w_hbm)`. Undefined. Sequential lowering may still emit an
allocation and a read; that does not make the program well-defined.

### 10.3 Concurrent without an event is not a data dependence

```text
Concurrent(
  T1:  stream(w_ssd → w_hbm);          // produces e1
  T2:  compute(unpack w_hbm)           // no wait
)
```

There is no SW edge. `T1` and `T2` are unordered. The read is undefined,
**even if `T1` is written above `T2` in the file.**

The well-defined form is:

```text
Concurrent(
  T1:  e1 = stream(w_ssd → w_hbm)
  T2:  wait e1; compute(unpack w_hbm)
)
```

```text
T1  →SW  wait_in_T2  →PO  compute
```

### 10.4 Sequential schedule is legal

For the well-defined program in 10.3, both

```text
T1 then T2
T2's wait-ready prefix, then T1, then T2's continuation
```

are in `ValidSchedules` only if they respect HB. `T2` cannot pass its
wait before `T1` completes. Any linear extension that keeps
`stream → wait → compute` is legal. Executing `T1` and the pre-wait
part of `T2` in parallel is also legal.

---

## 11. Relation to Phase 2A (realization, not definition)

| This document | Phase 2A baseline |
| ------------- | ----------------- |
| `→HB` | Not preserved; waits erased after producers are made synchronous |
| `Concurrent` = no ordering requirement | One linear extension (IR order) |
| Transfer event ⇒ `Valid(dest)` | Blocking copy, then erase the event |
| Lexical sibling order ∉ HB | Used as a convenient linear extension |

```text
Sequential lowering  ≠  this definition  ≠  a later parallel realization
```

A later parallel realization must preserve `→HB` and validity. It may
run any schedule in `ValidSchedules`. It must not invent HB from file
order.

---

## 12. What Phase 2B may implement (after this spec is approved)

Phase 2B is an *implementation* of §3–§8, not a redesign.

It may realize:

- `event` as a runtime completion object
- `wait` as an await of that object
- `Task` as a schedulable region
- `Concurrent` as unordered launch of children, with SW edges only
  where this document puts them

It must not:

- treat sibling textual order as dependence
- treat `materialize` as a fill
- drop `wait` unless producers have been made synchronous *and* the
  chosen schedule still respects the original `→HB` (the Phase 2A
  special case)

---

## 13. Executable semantic tests

`--check-s2c2-execution` is the v0.1 `MustProve` oracle. It does **not**
lower tokens. Files: `test/Semantics/e1.mlir` … `e8.mlir`.

| ID | Claim | Expected |
| -- | ----- | -------- |
| E1 | `materialize` then unpack/compute, no write | Undefined (no `Valid`) |
| E2 | `stream` + `wait` + unpack | Defined; dest valid after the event |
| E3 | `Concurrent(T1 stream, T2 compute)` without wait | Undefined; no HB |
| E4 | Same as E3 with `wait event(T1)` in T2 | Defined; `T1 →HB T2` |
| E5 | `Concurrent` with no events | Both sibling orders are legal schedules |
| E6 | Pipeline `S1` then `S2` | `S1 →HB S2` by construct |
| E7 | Sibling textual order without an event | Does **not** establish HB |
| E8 | Pipeline `S1` unpack then `S2` pack | Undefined; `StageOrder` is directed |

E3/E7 keep lexical concurrent order out of HB. E6/E8 lock directed
`StageOrder` (see [`pipeline-semantics.md`](pipeline-semantics.md)).
