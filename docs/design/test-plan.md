# Test Plan

Executable tests live under `test/` and run via `check-s2c2` (llvm-lit + FileCheck).

## Storage

| ID | File | Checks |
| -- | ---- | ------ |
| S1 | `test/Storage/ops.mlir` | Round-trip `alloc`/`dealloc`/`pack`/`unpack` |
| S2 | `test/Storage/invalid.mlir` | Unpack payload type must match buffer source type |
| S3 | `test/Storage/ops.mlir` | `object` / `materialize` / `transfer` round-trip |
| S4 | `test/Storage/invalid.mlir` | Materialize / transfer payload must match |
| S5 | `test/Comm/invalid.mlir` | Stream requires the same logical object |

## Compute

| ID | File | Checks |
| -- | ---- | ------ |
| C1 | `test/Compute/ops.mlir` | Round-trip `matmul`, `elemwise`, `gated_mlp` |
| C2 | `test/Conversion/expand-comp-composites.mlir` | Optional fused-candidate expansion |

## Communication

| ID | File | Checks |
| -- | ---- | ------ |
| M1 | `test/Comm/ops.mlir` | Round-trip `copy`, `stream`, `barrier` |
| M2 | `test/Comm/invalid.mlir` | Stream src/dst payload types must match |
| M3 | `test/Comm/ops.mlir` | Object-backed stream; async `copy -> !sched.token` |

## Schedule

| ID | File | Checks |
| -- | ---- | ------ |
| H1 | `test/Schedule/ops.mlir` | Round-trip `wait`, `overlap`, `pipeline`, `stage` |
| H2 | `test/Schedule/ops.mlir` | `concurrent` + `task` with value + token results |
| H3 | `test/Schedule/invalid.mlir` | Task yield operands must match task values |
| H4 | `test/Schedule/invalid.mlir` | `concurrent` body may only contain `sched.task` or `async.execute` |

## Conversion

| ID | File | Checks |
| -- | ---- | ------ |
| V1 | `test/Conversion/stor-to-memref.mlir` | Default map: `hbm` → `memref<..., 3>`; pack/unpack |
| V2 | `test/Conversion/stor-to-memref.mlir` | Override `space-map=hbm=9,ssd=100`; materialize/transfer |
| V3 | `test/Conversion/comp-to-linalg.mlir` | matmul / elemwise / gated_mlp → linalg |
| V4 | `test/Conversion/sequentialize-schedule.mlir` | overlap communicate-first; concurrent IR order |
| V5 | `test/Conversion/comm-to-memref.mlir` | stream/copy → memref.copy; wait erased |

## Integration

| ID | File | Checks |
| -- | ---- | ------ |
| I1 | `test/Integration/gated_mlp_ssd_stream.mlir` | Object identity, HBM replicas, concurrent gated MLP + stream |
| I2 | same file `--s2c2-lower` | Lowers to linalg + memref.copy + bufferization.to_tensor |

## Execution semantics (`--check-s2c2-execution`)

See [`execution-semantics.md`](execution-semantics.md) §13. Oracle only;
not token → async lowering.

| ID | File | Checks |
| -- | ---- | ------ |
| E1 | `test/Semantics/e1.mlir` | `materialize` then unpack, no write → undefined |
| E2 | `test/Semantics/e2.mlir` | `stream` + `wait` + unpack → dest valid |
| E3 | `test/Semantics/e3.mlir` | Concurrent stream ∥ unpack without wait → undefined |
| E4 | `test/Semantics/e4.mlir` | Wait producer task event → defined |
| E5 | `test/Semantics/e5.mlir` | Both sibling orders of event-free concurrent are legal |
| E6 | `test/Semantics/e6.mlir` | Pipeline `S1` write →HB `S2` read |
| E7 | `test/Semantics/e7.mlir` | T1-before-T2 textual order without event → undefined |
| E8 | `test/Semantics/e8.mlir` | Pipeline `S1` read then `S2` write → undefined (directed StageOrder) |

Pipeline contract: [`pipeline-semantics.md`](pipeline-semantics.md)
(v0.1 frozen). Lowering: chained await, not unordered executes.

## Token → async (HB-preserving slice)

| ID | File | Checks |
| -- | ---- | ------ |
| A2 | `test/Conversion/token-to-async-e2.mlir` | stream+wait → execute + await before unpack |
| A3 | `test/Conversion/token-to-async-e3.mlir` | no wait ⇒ no await (no invented HB) |
| A4 | `test/Conversion/token-to-async-e4.mlir` | wait(event(T1)) → await of T1 execute token |
| A5 | `test/Conversion/token-to-async-a5.mlir` | nested inner execute; PO before stream and after wait |
| A6 | `test/Conversion/token-to-async-a6.mlir` | task-local stream operands remapped into nested copy |
| A7 | `test/Conversion/token-to-async-a7.mlir` | no flatten when src/dst are defined inside the task |

## Concurrent → async (HB-preserving slice 2)

| ID | File | Checks |
| -- | ---- | ------ |
| C1 | `test/Conversion/concurrent-to-async-c1.mlir` | no-wait siblings: two executes, no await |
| C2 | `test/Conversion/concurrent-to-async-c2.mlir` | each sibling remaps its own task-local SSA |
| C3 | `test/Conversion/concurrent-to-async-c3.mlir` | consumer awaits producer token; parent awaits result value |

## Pipeline → async (v0.1 StageOrder)

| ID | File | Checks |
| -- | ---- | ------ |
| P1 | `test/Conversion/pipeline-to-async-p1.mlir` | await S1 (pack) before S2 unpack |
| P2 | `test/Conversion/pipeline-to-async-p2.mlir` | three stages, await between each execute |
| P3 | `test/Conversion/pipeline-to-async-p3.mlir` | stage-local SSA remapped; S2 awaits S1 |
