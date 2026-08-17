# S²C² IR (`s2c2ir`)

Out-of-tree MLIR dialect family for:

```text
S²C² = Storage + Schedule + Compute + Communication
```

This repository follows the official MLIR `examples/standalone` project
layout. It does **not** fork XLA, TVM, or IREE. IREE is a Phase 3 runtime
backend; StableHLO is a Phase 2C compute frontend (after semantic
normalization and native lowering).

## Phase 1 dialects

| Dialect | Namespace | Answers |
| ------- | --------- | ------- |
| `stor`  | `mlir::s2c2::stor`  | Where is data stored? |
| `comp`  | `mlir::s2c2::comp`  | What is computed, on which unit? |
| `comm`  | `mlir::s2c2::comm`  | How does data move? |
| `sched` | `mlir::s2c2::sched` | When does it run, and how is compute/comm overlapped? |

## Phase 1.5 semantics

| Contract | IR |
| -------- | -- |
| Logical identity | `!stor.object<tensor<...>>` |
| Residency | `!stor.buffer<tensor<...>, space>` via `materialize` / `transfer` |
| Completion event | `!sched.token` (task, stream, optional copy) |
| Concurrency | `sched.concurrent` + `sched.task` |
| Target memref spaces | `--convert-stor-to-memref="space-map=hbm=9,..."` |
| Fused MLP | keep `comp.gated_mlp`; opt-in `--expand-comp-composites` |

Design notes: [`docs/design/phase1.5-semantic-normalization.md`](docs/design/phase1.5-semantic-normalization.md)

## Requirements

- CMake >= 3.20
- Ninja
- LLVM/MLIR **20.1.x**
- `FileCheck` (LLVM utils or `llvm-*-tools`) and `lit` (`pip install lit`)

The most portable prefix is a source build with utils installed:

```sh
./scripts/bootstrap-llvm.sh
```

The GitHub `LLVM-*-Linux-X64.tar.xz` release also ships MLIR. Those libraries
are LTO bitcode built against **libc++**, so configure with
`-stdlib=libc++ -fuse-ld=lld -flto` and the tarball's `lib/<triple>` libc++ path.

## Build

```sh
cmake -G Ninja -S . -B build \
  -DMLIR_DIR=$PWD/third_party/llvm-install/lib/cmake/mlir \
  -DLLVM_EXTERNAL_LIT=$(command -v lit) \
  -DCMAKE_BUILD_TYPE=Release

cmake --build build --target s2c2-opt
cmake --build build --target check-s2c2
```

If LLVM is already installed elsewhere, point `MLIR_DIR` at
`<prefix>/lib/cmake/mlir`. Some prebuilt packages export `zstd::libzstd_static`;
the top-level CMakeLists maps that to the system `libzstd` when needed.

## Tools

- `s2c2-opt` — parse, verify, and transform S²C² IR
- `s2c2-translate` — translation driver (Phase 1 stub)

Round-trip an example:

```sh
./build/bin/s2c2-opt test/Integration/gated_mlp_ssd_stream.mlir
```

## Roadmap

See [`docs/roadmap.md`](docs/roadmap.md).

```text
StableHLO          (Phase 2C frontend, optional)
    ↓
S²C² IR            (stor / comp / comm / sched)
    ↓
MLIR standard      memref, linalg, async, mpi, scf, vector, transform
    ↓
IREE / LLVM        (Phase 3 runtime / backends)
```
