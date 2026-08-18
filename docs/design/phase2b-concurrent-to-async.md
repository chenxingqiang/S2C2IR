# Phase 2B (slice 2): concurrent → N × async.execute

Status: **implementation**. Realizes `NoOrderingRequirement`; does not
redefine Execution Semantics.

Acceptance criterion for this slice:

```text
HB-preserving concurrent lowering
```

not “async concurrent works.”

```text
sched.concurrent { task A; task B; task C }
        ↓
async.execute A
async.execute B
async.execute C
```

Out of scope here:

- `sched.pipeline` / `sched.overlap`
- nested structured schedule
- Conflict / race analysis
- changing slice 1 token / wait / flatten contracts

Prerequisite: [`phase2b-token-to-async.md`](phase2b-token-to-async.md).

## 1. What is preserved

| S²C² | After this pass |
| ---- | --------------- |
| Concurrent sibling | Sibling `async.execute` (no extra await) |
| Lexical sibling order | Still not HB |
| Cross-sibling `wait` | `async.await` of the producer execute token **inside** the consumer |
| Task-local SSA | Clone / remap inside that task's execute |
| Concurrent result values | `async.await` of `!async.value<T>` at the concurrent's original point |

Unused child tokens are **not** awaited at the parent. No wait ⇒ no
await (same rule as slice 1). Join-all of unused siblings would not
create sibling HB, but it would invent waits the source program did
not write.

`SequentialSchedule ∈ ValidSchedules` still holds: launching several
`async.execute` ops does not require parallel execution.

## 2. Rewrite

Run after `--convert-s2c2-token-to-async` (or on mixed IR: leftover
`sched.task` next to already-lowered `async.execute`).

Each direct child of `sched.concurrent`:

- already `async.execute` → hoist to the concurrent's insertion point
- remaining `sched.task` → one `async.execute` (body clone / remap)

Cross-sibling token uses go through `IRMapping`. A wait that used to
consume `event(T1)` becomes `async.await` of T1's execute token
**inside** T2, not an `async.execute [%t1]` dependency and not a
parent-level await before T2 is launched.

A4 flatten still applies to a valueless child when it is a single
transfer (or a leftover execute) whose captured operands are **external
to that task**. Task-local operands take the nested-execute fallback
(A7), so exploding concurrent cannot hoist stale SSA.

Valued children become:

```text
%token, %val = async.execute -> !async.value<T> {
  ...
  async.yield %v : T
}
```

Only if `sched.concurrent` yields that value does the parent
`async.await %val`. That await is the concurrent region's result, not
a sibling-to-sibling edge.

Pipeline / overlap / nested concurrent are not rewritten. Direct
children that are not `sched.task` or `async.execute` fail the pass.

## 3. Tests

| ID | Must show |
| -- | --------- |
| C1 | no-wait siblings: two executes, **no** `async.await` (no false HB) |
| C2 | each sibling remaps its own task-local `src`/`dst` |
| C3 | consumer execute `async.await`s the producer token; parent only awaits the result value |

E3 / E4 remain valid on `--convert-s2c2-token-to-async` alone (slice 1
leaves `sched.concurrent`). C1 / C3 are the concurrent-exploded forms.
