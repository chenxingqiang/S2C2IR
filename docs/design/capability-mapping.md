# Hardware Capability / Target Mapping (v0.1)

Status: **design + first verification matrix**. Does **not** change
Phase 2B execution semantics. Prerequisite contracts are frozen:

[`execution-semantics.md`](execution-semantics.md),
[`pipeline-semantics.md`](pipeline-semantics.md),
[`phase2b-composition.md`](phase2b-composition.md).

```text
Capability mapping  ≠  execution semantics
Target profile      =  one legal realization of frozen HB
```

```text
HB = TC(PO ∪ SW ∪ ConstructOrder)
```

A profile may pick any schedule in `ValidSchedules`. Lowering must
preserve `HB_source ⊆ HB_lowered` for the edges the source actually
wrote (implementation correctness: a backend may be more conservative).
That `⊆` is **not** Realization Space membership. `R(P, D)` requires
`HB_M = HB_source`; see [`realization-space.md`](realization-space.md).
A profile must not invent sibling HB, treat `materialize` as a fill, or
add StageResult / SoftPipe / InstanceOrder / race analysis.

---

## 1. Why this is not a new semantic core

Phase 2B already answered *when* effects may become visible. Capability
mapping answers *which existing lowering* is a legal reading of that
contract on a class of targets.

```text
CPU-like sequential     SequentialSchedule ∈ ValidSchedules
GPU-like async          Token SW + Concurrent unordered execute
NPU-like staged DMA     Pipeline StageOrder + transfer payload
multi-residency comm    comm between distinct objects / spaces
SSD → DRAM → Device     logical spaces + target space-map
```

These names are **profiles**, not dialects. v0.1 does not add a device
IR, MPI, CUDA ABI, or IREE HAL. Phase 3 may bind a profile to a runtime.

```text
S²C² semantic IR
      │
      ├── cpu-seq     --s2c2-lower
      ├── gpu-async   token + concurrent + pipeline → async
      └── space-map   --convert-stor-to-memref=space-map=...
```

`--s2c2-lower` remains a blocking approximation (tokens dropped because
copies are synchronous). Async lowering remains HB-preserving. Neither
redefines Token / Concurrent / Pipeline.

---

## 2. Profiles (v0.1)

| ID | Profile | Existing pipeline | Must prove | Must not claim |
| -- | ------- | ----------------- | ---------- | -------------- |
| T1 | cpu-seq | `--s2c2-lower` | blocking `memref.copy`; no `async.execute` / `sched.wait` | that sequentialization is the S²C² definition |
| T2 | gpu-async | `--convert-s2c2-token-to-async` `--convert-s2c2-concurrent-to-async` `--convert-s2c2-pipeline-to-async` | prefetch SW, StageOrder await, `CHECK-NOT: async.await` between S2 siblings | that execute implies MustRunParallel |
| T3 | npu-staged-dma | same as T2 | StageOrder is chained await; stream becomes copy inside execute | a new DMA dialect; `engine` surviving lowering |
| T4 | multi-residency comm | T1 or T2 | two logical objects stay two allocations; copies stay between their residencies | MPI / multi-device runtime |
| T5 | SSD→DRAM→Device | T1 with `space-map` and/or a hop chain `ssd → dram → hbm` | integer memref spaces come from the **target map**, not `#stor.space` discriminants | that `hbm=3` is a hardware ABI |

`#comm.engine<dma>` may appear on **source** `comm.stream`. Token
lowering wraps a bare `comm.copy` and does not keep the engine attribute.
That is accepted in v0.1: engine is a source annotation, not an HB edge.

Unused pure compute inside a valueless concurrent task may disappear
under `--s2c2-lower` (no side effect, no yielded value). That is DCE of
a realization, not a dropped SW / StageOrder edge on residencies that
the parent still reads.

---

## 3. Shared source program

The composition program (X1) is the default matrix input:

```text
SSD prefetch (stream + wait)     Token / SW
      ▼
Pipeline S1 pack activations     StageOrder
      ▼
Pipeline S2
  Compute unpack ∥ Comm spill    Concurrent, distinct residencies
      ▼
Pipeline done → parent unpack
```

A second function covers the hop chain without new constructs:

```text
pack SSD → wait stream DRAM → wait stream HBM → unpack HBM
```

That is two Token SW edges on one object. Spaces `ssd`, `dram`, `hbm`
are already in `#stor.space`. `hbm` stands in for “device memory” in
v0.1; there is no `#stor.space<device>`.

---

## 4. Out of scope

```text
StageResult / cross-stage SSA
iteration IR / InstanceOrder / SoftPipe
race / conflict analysis
MPI, IREE HAL, CUDA, NPU ISA
new pass --s2c2-map-capability
new storage spaces
```

A later capability pass, if any, may only **select** among T1–T5. It
must not add HB axioms.

Cost / resource scoring of legal mappings is
[`cost-resource-model.md`](cost-resource-model.md) (v0.1–v0.3 frozen).
The set of legal mappings is
[`realization-space.md`](realization-space.md) (**v0.4.0 frozen**).
Search / Pareto over that set is [`search-pareto.md`](search-pareto.md)
(**v0.4.1 frozen**). Listing members inside a finite family is
[`realization-enumerator.md`](realization-enumerator.md)
(**v0.4.2 frozen**). Listing `ArgMin_F` / `Pareto_F` is
[`realization-argmin-pass.md`](realization-argmin-pass.md)
(**v0.4.4 frozen**). Search Space / `Neighbor` / legality
preservation are [`search-space.md`](search-space.md) (v0.4.5).
These layers do not redefine HB.

---

## 5. Tests

| ID | File | Profile |
| -- | ---- | ------- |
| T1 | `test/Conversion/capability-matrix.mlir` `--s2c2-lower` | cpu-seq |
| T2 | same file, three async passes | gpu-async / npu-staged-dma shape |
| T5 | same file `--s2c2-lower=space-map=...` | SSD/HBM integers from the map |
| T5b | `@ssd_dram_hbm_hops` | SSD→DRAM→HBM Token chain + space-map |

T2 FileCheck includes `CHECK-NOT: async.await` between S2 sibling
launches (same Concurrent invariant as X1). T4 is implied by T1/T2:
two objects, four allocations, copies SSD↔HBM.

### IsLegal(P, D, M) on F_0 axes

`M = (sched, spaceMap, device)`. Shared oracle:
`isLegalRealization` in [`S2C2Legality.h`](../../include/s2c2/S2C2Legality.h).
Does not redefine HB. T1/T2/T3 pairing:

```text
cpu-seq          ↔  cpu, cim
gpu-async        ↔  gpu
npu-staged-dma   ↔  npu
default, t5      legal maps
```

`M ∈ F` is not `IsLegal`. Enumerator / Search / Placement must call
this predicate; they must not grow a second matrix.
