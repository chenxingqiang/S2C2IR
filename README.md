# S²C² IR (`s2c2ir`)

Out-of-tree MLIR dialect family for:

```text
S²C² = Storage + Schedule + Compute + Communication
```

This repository follows the official MLIR `examples/standalone` project
layout. It does **not** fork XLA, TVM, or IREE. IREE is a Phase-2 runtime
backend; StableHLO is a Phase-2 compute frontend.

## Phase 1 dialects

| Dialect | Namespace | Answers |
| ------- | --------- | ------- |
| `stor`  | `mlir::s2c2::stor`  | Where is data stored? |
| `comp`  | `mlir::s2c2::comp`  | What is computed, on which unit? |
| `comm`  | `mlir::s2c2::comm`  | How does data move? |
| `sched` | `mlir::s2c2::sched` | When does it run, and how is compute/comm overlapped? |

Design notes: [`docs/design/phase1-s2c2-core.md`](docs/design/phase1-s2c2-core.md)

## Requirements

- CMake >= 3.20
- Ninja
- LLVM/MLIR **20.1.x** (built with `-DLLVM_INSTALL_UTILS=ON` so `FileCheck` and `llvm-lit` are available)

Bootstrap a local LLVM/MLIR prefix:

```sh
./scripts/bootstrap-llvm.sh
```

## Build

```sh
cmake -G Ninja -S . -B build \
  -DMLIR_DIR=$PWD/third_party/llvm-install/lib/cmake/mlir \
  -DLLVM_EXTERNAL_LIT=$PWD/third_party/llvm-install/bin/llvm-lit \
  -DCMAKE_BUILD_TYPE=Debug

cmake --build build --target s2c2-opt
cmake --build build --target check-s2c2
```

If LLVM is already installed elsewhere, point `MLIR_DIR` at
`<prefix>/lib/cmake/mlir`.

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
StableHLO          (Phase 2 frontend)
    ↓
S²C² IR            (this repo: stor / comp / comm / sched)
    ↓
MLIR standard      memref, linalg, async, mpi, scf, vector, transform
    ↓
IREE / LLVM        (Phase 3 runtime / backends)
```
