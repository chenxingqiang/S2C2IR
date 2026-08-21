# Phase 2B composition verification

Status: **verification**. Does not add or change Token / Concurrent /
Pipeline contracts. Those remain frozen.

```text
Token + Concurrent + Pipeline can compose without semantic interference
```

Foundation (do not reopen):

```text
Token        = Event / Completion / Synchronization   → SW
Concurrent   = NoOrderingRequirement                  → no sibling HB
Pipeline     = Ordered valueless stages               → StageOrder HB
HB           = TC(PO ∪ SW ∪ ConstructOrder)
```

Frozen / out of scope: `StageResult`, cross-stage SSA, iteration IR,
InstanceOrder realization, SoftPipe, overlap optimization, race /
conflict analysis.

## 1. What is being checked

One S²C² program uses all three constructs:

```text
SSD Prefetch                 Token: stream + wait
      │
      ▼
Pipeline Stage 1             StageOrder
      │
      ▼
Pipeline Stage 2
      ├───────────────┐
      ▼               ▼
 Compute           Communication     Concurrent: NoOrderingRequirement
      │               │
      └──── join at stage completion ────┘
                      │
                      ▼
                 Pipeline Done
```

Constraints that follow from the frozen contracts, not new rules:

- Pipeline body contains only `sched.stage`. Concurrent lives **inside**
  a stage.
- Stages and the pipeline are **valueless**. Cross-stage data is
  residency / event, not SSA.
- Concurrent siblings do not write the same residency. Unordered
  conflicting writes are future Conflict / Race Semantics.

## 2. Expected composition

| Source edge | Must survive |
| ----------- | ------------ |
| Prefetch `wait` | SW before pipeline entry |
| `S1 → S2` | `StageOrder` (await S1 before S2 execute) |
| Compute ∥ Comm inside S2 | Sibling `async.execute` with **no** await between launches |
| Stage / pipeline completion | Join unused inner tokens at **end** of S2; await last stage |

That join is stage completion (parent PO), not a sibling HB edge.

Pass order for the lowering test:

```text
--convert-s2c2-token-to-async
--convert-s2c2-concurrent-to-async
--convert-s2c2-pipeline-to-async
```

## 3. Tests

| ID | File | Oracle |
| -- | ---- | ------ |
| X1 source | `test/Semantics/compose-token-pipeline-concurrent.mlir` | `--check-s2c2-execution` |
| X1 lowered | `test/Conversion/compose-token-pipeline-concurrent.mlir` | chained StageOrder + unordered siblings inside S2 (`CHECK-NOT: async.await` between the two launches) |
