# Phase 2B (slice 1): HB-preserving token lowering

Status: **frozen**. Realizes events; does not redefine Execution
Semantics.

Acceptance criterion for this slice:

```text
HB-preserving lowering
```

not “async lowering works.”

```text
!sched.token  →  !async.token
sched.wait    →  async.await
```

Out of scope here:

- `sched.concurrent` → several `async.execute` (slice 2:
  [`phase2b-concurrent-to-async.md`](phase2b-concurrent-to-async.md))
- `sched.pipeline` / `sched.overlap`
- `comm.stream` → memref / DMA runtime
- Conflict / race analysis

## 1. What is preserved

| S²C² | After this pass |
| ---- | --------------- |
| Transfer / valueless-task event | `async.execute` token |
| `wait e` | `async.await` of that token |
| No wait | No await (no invented SW) |
| Concurrent sibling order | Still not HB |

`async.execute` may run its body concurrently with the successor; sequential
execution remains legal (`SequentialSchedule ∈ ValidSchedules`).

## 2. Rewrite

**Token producer** (func-level `comm.stream` / token `comm.copy`, or a
`sched.task` with no value results):

```text
%e = comm.stream %src, %dst -> !sched.token
```

```text
%e = async.execute {
  comm.copy %src, %dst
  async.yield
} : !async.token
```

The execute token *is* the transfer event. The inner `comm.copy` is a
blocking payload, not Phase 2A `memref.copy`.

A waited valueless task is represented by one `async.execute`; its task
completion is that execute token. Token-producing inner operations
(`comm.stream`, token `comm.copy`) keep their own events **inside that
same region**: each becomes a nested `async.execute`. The old
`!sched.token` **and** the producer's `src`/`dst` operands are remapped
(`lookupOrDefault`) so an inner `wait` stays a `SW`, Task PO is
preserved, and task-local buffers are not left as stale SSA. If the
task body is only one such transfer, has no inner wait, **and** the
transfer operands are defined outside the task, the task event and the
transfer event are the same token (E4 flatten). Task-local operands
fall back to nested `async.execute` plus an await of the inner event
at task completion (A7).

**Wait:**

```text
sched.wait %e1, %e2
```

```text
async.await %e1 : !async.token
async.await %e2 : !async.token
```

Both awaits sit on the same PO point as the original wait (set wait).

**Valued `sched.task` and unwaited valueless tasks:** kept. A *waited*
valueless task is itself an event and becomes `async.execute`.
`sched.concurrent` is not rewritten; its verifier allows leftover
`async.execute` children next to remaining tasks.

## 3. Tests (E2 / E3 / E4)

| ID | Must show |
| -- | --------- |
| E2 | `async.await` of the stream/execute token before unpack |
| E3 | sibling unpack has **no** `async.await` (no false HB) |
| E4 | consumer task `async.await`s the producer execute token |
| A5 | inner `stream`+`wait` remaps to `await` of the inner execute token |
| A6 | task-local `src`/`dst` are remapped into the nested `comm.copy` |
| A7 | task-local operands reject A4 flatten; nested execute + await |

E1 / E5 / E6 / E7 stay on `--check-s2c2-execution` (semantic IR).
