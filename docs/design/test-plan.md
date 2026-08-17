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

## Conversion

| ID | File | Checks |
| -- | ---- | ------ |
| V1 | `test/Conversion/stor-to-memref.mlir` | Default map: `hbm` → `memref<..., 3>` |
| V2 | `test/Conversion/stor-to-memref.mlir` | Override `space-map=hbm=9,ssd=100`; materialize/transfer |

## Integration

| ID | File | Checks |
| -- | ---- | ------ |
| I1 | `test/Integration/gated_mlp_ssd_stream.mlir` | Object identity, HBM replicas, concurrent gated MLP + stream |
