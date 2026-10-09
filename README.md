# S²C² IR

S²C² IR is an out-of-tree MLIR project for one question: what is stored, computed, moved, and ordered, and which of those choices are legal on a device.

```text
stor   where the data lives
comp   what is computed
comm   how data moves
sched  which events must happen before others
```

`sched` is the happens-before layer. It is not a fourth data dialect. `sched.concurrent` means there is no ordering requirement. It is not a promise that the hardware runs those tasks at the same time.

This tree does not fork XLA, TVM, or IREE. IREE is a possible runtime backend, not the definition of the IR.

## Architecture

Five products sit in one order. A later product may carry an earlier result. It may not redefine it.

```text
        Semantic IR          Evidence / Capability          Hardware
              │                        │                        │
              └────────────────────────┼────────────────────────┘
                                       ▼
                              Realization engine
                                       ▼
                            Schedule / Transform
                                       ▼
                                    Backend
```

| Product | Question | Where it stands |
| ------- | -------- | --------------- |
| Semantic IR | What is stored, computed, moved, and ordered? | Frozen as `stor`, `comp`, `comm`, `sched`. |
| Evidence / Capability | What can this device do, and under which evidence? | Frozen. No evidence means no destructive rewrite. |
| Realization | Which implementations are legal for program `P` on device `D`? | Frozen. A legal `M` keeps the source happens-before. |
| Optimization | Which legal candidate is sufficient, authorized, and transformed? | The only open mainline. It does not jump from a cost score to a rewrite. |
| Backend | How does a realization become a runtime or a kernel? | Not a semantic definition. It must not invent a new one. |

A candidate moves only in this order:

```text
legal
  → sufficient
  → authorized
  → rewrite-plan
  → apply, or stop
```

`sufficient` is not `authorized`. `authorized` is not a rewrite license. A rewrite plan names KEEP → EVICT → TRANSFER → RESTORE and still does not apply it. Apply is a separate host.

That host, W0-3/2, is one pattern: one device, one contiguous region, capacity 2. It matches a plan, builds a candidate without editing the source, checks a happens-before projection and an external witness, then commits or discards. `can-run-plan` stays `no` even when apply succeeds.

```text
dialect module                         s2c2-opt
stor / comp / comm / sched             parse, verify, sequential lower

carrier text                           not a dialect in s2c2-opt
        │
        ▼
host program                           fields evaluate_apply already reads
        │
        ▼
evaluate_apply                         the W0-3/2 host only
```

The two pictures are not one automatic compiler. `s2c2-opt` checks the four dialects. The carrier text is a projection into the host. The host does not parse MLIR, and the optimizer does not call `evaluate_apply`.

## Direction and current goal

The research direction matches the industry report: a token path that crosses storage, compute, communication, and execution needs a composition semantics, and a vendor stack is a realization of that semantics.

The delivery on this tree is narrower. It is done when the dialect ops stay as they are, the apply host stays W0-3/2, `can-run-plan` stays `no`, the carrier text stays separate from `s2c2-opt`, and `next_cut` stays `NOT OPENED`. Token Path, MoE dispatch, cluster topology, and CIM compute stay research sketches. They are not a contract and not an inhabitant.

The boundary, including the ops the report sketches but this tree does not have, is [`docs/design/goal-alignment-v1.md`](docs/design/goal-alignment-v1.md).

## Start here

You can check the frozen host without building LLVM. From the repository root:

```sh
python3 runtime/record_semantic_baseline.py --print-semantic-baseline-summary
python3 runtime/record_apply_scenario.py --print-apply-scenario
python3 runtime/record_storage_apply.py --print-apply-contract
python3 runtime/record_mlir_carrier.py --print-carrier-extract
python3 runtime/record_compiler_spine.py --print-compiler-spine
python3 runtime/record_goal_alignment.py --print-goal-alignment
```

| Command | What you should see |
| ------- | ------------------- |
| semantic baseline | `result PASS`. This replays the frozen decision stack. It does not apply IR. |
| apply scenario | The acceptance case `w0-3-2-storage-capacity-001`. `can-run-plan` stays `no`. |
| apply contract | The W0-3/2 host: one region, capacity 2, then KEEP → EVICT → TRANSFER → RESTORE. |
| carrier extract | The same host result, read back from a text carrier. `host-matrix-through-carrier 29`. |
| compiler spine | `spine-match yes`, `can-run-plan no`, `host-matrix-through-spine 29`. An opt flag or a text that is not one W0-3/2 region never reaches the host. |
| goal alignment | `goal-alignment PASS`. The design page, this README, and the three status slides name the same cut. `next-cut NOT-OPENED`. |

The carrier is a text projection onto the program `evaluate_apply` already accepts. It is not a new semantic model, and `s2c2-opt` does not register it. `stor.transfer` in MLIR is a residency copy. The host string `"transfer"` is a different step, produced by the host when it builds a candidate.

Semantic baseline remains `36fd6fd931c109c6849cc366bd91b5abdfcab4b1`. Later documentation and the carrier extract do not replace that baseline.

## What this repository will not do for you

- It will not plan a run. `can-run-plan` stays `no`.
- It will not turn a profiler trace into a compiler happens-before edge.
- It will not treat an API name as the device kernel that ran.
- It does not express every distributed or collective program. The W0-3/2 host is one device and one contiguous region. A larger workload sitting outside that host is a scope boundary, not by itself a new contract.
- Search, generic rewrite, and a storage-schedule inhabitant stay closed.

The evidence page records that limit: [`docs/design/empirical-semantic-boundary-v1.md`](docs/design/empirical-semantic-boundary-v1.md).

## Build the compiler

You need CMake ≥ 3.20, Ninja, LLVM/MLIR **20.1.x**, plus `FileCheck` and `lit` (`pip install lit`).

A source build that also installs the LLVM utils:

```sh
./scripts/bootstrap-llvm.sh
```

The GitHub `LLVM-*-Linux-X64.tar.xz` release also ships MLIR. Those libraries are LTO bitcode built against **libc++**, so configure with `-stdlib=libc++ -fuse-ld=lld -flto` and the tarball's `lib/<triple>` libc++ path.

```sh
cmake -G Ninja -S . -B build \
  -DMLIR_DIR=$PWD/third_party/llvm-install/lib/cmake/mlir \
  -DLLVM_EXTERNAL_LIT=$(command -v lit) \
  -DCMAKE_BUILD_TYPE=Release

cmake --build build --target s2c2-opt
cmake --build build --target check-s2c2
```

If LLVM is already installed, point `MLIR_DIR` at `<prefix>/lib/cmake/mlir`. Some prebuilt packages export `zstd::libzstd_static`; the top-level CMakeLists maps that to the system `libzstd` when needed.

`s2c2-opt` parses and checks the four dialects. `--s2c2-lower` is a sequential, blocking lowering. It is not the semantic definition and not async lowering. `--check-s2c2-execution` checks the frozen execution contracts.

```sh
./build/bin/s2c2-opt test/Integration/gated_mlp_ssd_stream.mlir
./build/bin/s2c2-opt test/Integration/evidence-bounded-schedule.mlir \
  --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution
```

`s2c2-translate` is a translation driver stub. `s2c2-cuda-adapter` is a host dry-run for the CUDA pilot stand-in. Neither one is a device backend, and neither one applies the W0-3/2 host.

## Read next

| If you want | Read |
| ----------- | ---- |
| The product boundary | [`docs/design/compiler-spine.md`](docs/design/compiler-spine.md) |
| How to build and what each phase froze | [`docs/roadmap.md`](docs/roadmap.md) |
| The one apply pattern that is implemented | [`docs/design/ir-apply-inhabitant.md`](docs/design/ir-apply-inhabitant.md) |
| The carrier text and its tests | [`docs/design/mlir-carrier-v0.md`](docs/design/mlir-carrier-v0.md) |
| The carrier handoff into the host | [`docs/design/compiler-spine-integration.md`](docs/design/compiler-spine-integration.md) |
| Storage, compute, communication, and events | [`docs/design/execution-semantics.md`](docs/design/execution-semantics.md) |
| What the hardware runs did and did not prove | [`docs/design/empirical-semantic-boundary-v1.md`](docs/design/empirical-semantic-boundary-v1.md) |
| Research direction versus this cut | [`docs/design/goal-alignment-v1.md`](docs/design/goal-alignment-v1.md) |

Phase histories, cost versions, and search contracts stay in those design notes. They are frozen unless a page says otherwise.
