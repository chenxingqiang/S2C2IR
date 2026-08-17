# Phase 1 Design: S²C² Core Dialects

Status: **implementation baseline** (out-of-tree MLIR, LLVM 20.1).

## 1. Problem

S²C² is a new IR abstraction:

```text
S²C² = Storage + Schedule + Compute + Communication
```

It answers questions that StableHLO does not:

| Question | Dialect |
| -------- | ------- |
| Where is data? | `stor` |
| What is computed, and on which unit? | `comp` |
| How does data move? | `comm` |
| When does it execute, and can compute overlap communication? | `sched` |

Phase 1 must validate these semantics **without** inheriting IREE Flow/Stream/HAL
so research attribution stays clean.

## 2. Project shape

Base: LLVM `mlir/examples/standalone` (component / out-of-tree build).

```text
s2c2ir/
├── include/s2c2/{Storage,Compute,Comm,Schedule,S2C2Passes.td}
├── lib/{Storage,Compute,Comm,Schedule,Conversion}
├── tools/{s2c2-opt,s2c2-translate}
└── test/{Storage,Compute,Comm,Schedule,Conversion,Integration}
```

C++ namespaces:

- `mlir::s2c2::stor`
- `mlir::s2c2::comp`
- `mlir::s2c2::comm`
- `mlir::s2c2::sched`

## 3. Type and attribute model

### 3.1 `!stor.buffer<sourceType, space>`

`sourceType` is a ranked tensor describing the logical payload.
`space` is a storage-space enum:

| Enum | Meaning |
| ---- | ------- |
| `register` | Register file |
| `sram` | On-chip SRAM |
| `dram` | Off-chip DRAM |
| `hbm` | High-bandwidth memory |
| `ssd` | Host/SSD backing store (streaming source) |
| `cim` | Compute-in-memory array |
| `host` | Host DRAM |

Example: `!stor.buffer<tensor<4096x11008xf16>, ssd>`

### 3.2 `!sched.token`

Asynchronous completion token produced by `comm.stream` / `comm.copy` and
consumed by `sched.wait`.

### 3.3 Compute attributes

- `#comp.unit<cpu|gpu|npu|cim>`
- `#comp.activation<silu|gelu|relu>`
- `#comp.elemwise<add|mul|silu|gelu>`

### 3.4 Communication attributes

- `#comm.kind<p2p|broadcast|reduce>`
- `#comm.engine<dma|copy|noc>`

## 4. Operations

### 4.1 Storage (`stor`)

| Op | Role |
| -- | ---- |
| `stor.alloc` | Allocate a buffer in a space (space lives on the result type) |
| `stor.dealloc` | Free a buffer |
| `stor.pack` | Write a tensor into a buffer |
| `stor.unpack` | Read a tensor from a buffer |

Compute stays on tensors. Placement is a Storage concern. `pack`/`unpack`
are the explicit tensor↔buffer edge so later lowering can target
`bufferization` / `memref`.

### 4.2 Compute (`comp`)

| Op | Role |
| -- | ---- |
| `comp.matmul` | High-level matmul (lowers to `linalg` later) |
| `comp.elemwise` | Elementwise / activation |
| `comp.gated_mlp` | First-class Gated MLP: `silu(x@Wg) * (x@Wu)` then `@ Wd` |

`comp.gated_mlp` is intentionally **not** expanded in Phase 1. The research
IR should name the fused kernel so schedule/storage decisions can attach to
it as a unit.

### 4.3 Communication (`comm`)

| Op | Role |
| -- | ---- |
| `comm.copy` | Blocking or token-producing buffer copy |
| `comm.stream` | Streaming transfer (SSD→HBM, DMA) producing `!sched.token` |
| `comm.barrier` | Synchronization |

`comm.stream` is the SSD-streaming primitive. Source and destination payload
types must match; spaces should differ.

### 4.4 Schedule (`sched`)

| Op | Role |
| -- | ---- |
| `sched.wait` | Wait on one or more tokens |
| `sched.yield` | Region terminator |
| `sched.overlap` | Two regions: compute and communicate, intended to overlap |
| `sched.pipeline` | Ordered pipeline body |
| `sched.stage` | Named pipeline stage |

`sched.overlap` is the Phase-1 embodiment of compute/comm overlap:

```mlir
%y = sched.overlap -> tensor<1x4096xf16> {
  sched.wait %prefetch : !sched.token
  %w = stor.unpack %hbm : !stor.buffer<tensor<...>, hbm> -> tensor<...>
  %out = comp.gated_mlp ...
  sched.yield %out : tensor<1x4096xf16>
} {
  %t = comm.stream %ssd, %hbm : ... -> !sched.token
  sched.yield
}
```

Results of `sched.overlap` match the compute-region `sched.yield` operands.
The communicate region is side-effecting (streams, copies).

## 5. Interfaces

- `stor::StorageResource` — ops that expose `getStorageSpace()`
- `sched::HasAsyncToken` — ops that produce a completion token

Phase 1 implementations are ODS-backed; more methods land with conversion.

## 6. Passes

| Pass | Purpose |
| ---- | ------- |
| `--convert-stor-to-memref` | `stor.alloc`/`stor.dealloc` → `memref.alloc`/`memref.dealloc`, mapping spaces to integer memory spaces |

Integer memory-space mapping (stable for tests):

```text
register=0, sram=1, dram=2, hbm=3, ssd=4, cim=5, host=6
```

Not in Phase 1: `S2C2ToLinalg`, `S2C2ToAsync`, `S2C2ToMPI`, `S2C2ToLLVM`
(directories reserved).

## 7. Lowering direction (not fully implemented)

```text
S²C² IR
  ├── stor ──────► memref
  ├── comp ──────► linalg ► vector / scf
  ├── comm ──────► mpi / async / memref.copy
  └── sched ─────► transform / async
```

## 8. Integration target

`test/Integration/gated_mlp_ssd_stream.mlir` must represent:

1. Weights live in `ssd`
2. Prefetch via `comm.stream` into `hbm`
3. `sched.overlap` of compute (`comp.gated_mlp`) and the next stream
4. Tokens connect stream completion to `sched.wait`

This is the Phase-1 research kernel: Gated MLP + SSD streaming + overlap.

## 9. Explicit non-goals

- Do not encode IREE Stream/HAL semantics in `sched`
- Do not fork StableHLO ops into `comp` (StableHLO remains a frontend)
- Do not model CIM arrays as CIRCT hardware yet; `cim` is only a storage /
  compute-unit enum
