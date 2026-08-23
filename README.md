# S²C² IR (`s2c2ir`)

Out-of-tree MLIR dialect family for:

```text
S²C² = Storage + Compute + Communication + Execution Semantics
```

Schedule is the happens-before / event constraint layer among the three
data and compute dimensions, not a fourth data dialect.

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
| Validity | `materialize` = allocated, uninitialized; transfer/copy/pack = dest valid |
| Completion event | `!sched.token` (task done, or dest valid after stream/copy) |
| Concurrency | `sched.concurrent` = no ordering requirement among `sched.task`s |
| Target memref spaces | `--convert-stor-to-memref="space-map=hbm=9,..."` |
| Fused MLP | keep `comp.gated_mlp`; opt-in `--expand-comp-composites` |

`--s2c2-lower` is a **sequential / blocking baseline**, not the semantic
definition and not async lowering.

Design notes: [`docs/design/phase1.5-semantic-normalization.md`](docs/design/phase1.5-semantic-normalization.md),
[`docs/design/phase2a-sequential-lowering.md`](docs/design/phase2a-sequential-lowering.md),
[`docs/design/execution-semantics.md`](docs/design/execution-semantics.md),
[`docs/design/pipeline-semantics.md`](docs/design/pipeline-semantics.md),
[`docs/design/phase2b-composition.md`](docs/design/phase2b-composition.md),
[`docs/design/capability-mapping.md`](docs/design/capability-mapping.md),
[`docs/design/cost-resource-model.md`](docs/design/cost-resource-model.md),
[`docs/design/cost-resource-model-v02.md`](docs/design/cost-resource-model-v02.md),
[`docs/design/cost-resource-model-v03.md`](docs/design/cost-resource-model-v03.md),
[`docs/design/realization-space.md`](docs/design/realization-space.md),
[`docs/design/search-pareto.md`](docs/design/search-pareto.md),
[`docs/design/realization-enumerator.md`](docs/design/realization-enumerator.md),
[`docs/design/realization-argmin-pass.md`](docs/design/realization-argmin-pass.md),
[`docs/design/search-space.md`](docs/design/search-space.md),
[`docs/design/search-algorithm-contract.md`](docs/design/search-algorithm-contract.md),
[`docs/design/search-start-policy.md`](docs/design/search-start-policy.md),
[`docs/design/search-algorithm.md`](docs/design/search-algorithm.md),
[`docs/design/search-walk-n1.md`](docs/design/search-walk-n1.md),
[`docs/design/search-restart-complete.md`](docs/design/search-restart-complete.md),
[`docs/design/search-pareto-nxt.md`](docs/design/search-pareto-nxt.md),
[`docs/design/search-verification.md`](docs/design/search-verification.md),
[`docs/design/realization-transform.md`](docs/design/realization-transform.md),
[`docs/design/realization-transform-reorder.md`](docs/design/realization-transform-reorder.md),
[`docs/design/realization-transform-compose.md`](docs/design/realization-transform-compose.md),
[`docs/design/pilot-benchmark.md`](docs/design/pilot-benchmark.md)

Phase 2B execution semantics (Token / Concurrent / Pipeline /
composition) are **frozen**. Realization Space `R(P, D)` is **frozen**
(`HB_M = HB_source`). Hardware capability mapping verifies legal
realizations; `--s2c2-cost` scores them against a device table and must
not redefine `→HB`. Search / Pareto may only select among `R`. A
Realization Enumerator (**v0.4.2 frozen**) may only list `R ∩ F` for a
declared finite family `F`; `--s2c2-enumerate` prints that set.
`--s2c2-argmin` prints set-valued `ArgMin_F` / `Pareto_F` over it.
Search Space / `Neighbor` (v0.4.5) generate candidates in `F` and
accept only `R ∩ F`. The Search Algorithm Contract (v0.4.6) names
the walk objects. StartPolicy / RestartPolicy (v0.4.7) name how a
walk enters `X`. The Algorithm object (v0.4.8) is
`A = (N, S, Rst, Nxt, Acc)`. `--s2c2-walk` (v0.4.9) is its first
inhabitant. v0.4.10 witnesses `LocalStop ⇏ ArgMin_F`. v0.4.11
adds `Nxt = first(Pareto(Frontier))` without changing Cost / HB /
`R` / Neighbor / Start / Restart. v0.4.12 verifies those
inhabitants (`--s2c2-walk=verify`). v0.5.0 (**frozen**) opens
`T : P → P' ∪ {⊥}` with `HB(P') = HB(P)` only when `T(P) ≠ ⊥`,
and rebuilt `X'` (`--s2c2-xform=kind=id`). v0.5.1 (**frozen**) adds
`--s2c2-xform=kind=concurrent-reorder` (HB-independent sibling
swap; executable HB equality). v0.5.2 (**frozen**) is the docs-only
composition contract `(T_b ∘ T_a)`: each step re-proves
`HB(P_i) = HB(P_0)` and rebuilds `X_i`. The Pilot
([`pilot-benchmark.md`](docs/design/pilot-benchmark.md)) is the
**frozen V1–V2** validation entry: three stand-in workloads on
that stack. It is not a new Search or Transform kind. V3/V4
need a real backend.

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

- `s2c2-opt` — parse, verify, and transform S²C² IR (`--s2c2-lower` for Phase 2A; `--check-s2c2-execution` for E1–E8 and Token+Concurrent+Pipeline composition; `--convert-s2c2-token-to-async` / `--convert-s2c2-concurrent-to-async` / `--convert-s2c2-pipeline-to-async` for HB-preserving event lowering; `--s2c2-cost` for frozen v0.1 scores; `--s2c2-cost-hb` for frozen v0.2 HB-aware pair credit; `--s2c2-cost-cp` for v0.3 critical-path scores)
- `s2c2-translate` — translation driver (stub)

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
