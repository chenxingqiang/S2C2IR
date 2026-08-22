# Realization Space (v0.4.0)

Status: **design + enumeration of already-legal mappings**. Does not
search, place, or rewrite. Does not redefine Token / Concurrent /
Pipeline. Cost v0.1–v0.3 remain frozen.

```text
v0.3  CanonicalRealizationCost(P, D, HB, π)    FROZEN
v0.4.0  R(P, D) = legal realization set        this document
v0.4+   Search / Pareto over R                 later
```

```text
Cost Model cannot add HB
CanonicalRealizationCost ≠ Optimization
π ≠ OptimalSchedule
Hardware Capability ≠ Hardware Semantics
```

---

## 1. Why this layer exists

Frozen Cost already answers *how good is this (P, D) under canonical
π?* It does not answer *which mappings are allowed to exist*.

```text
IsLegal(P, D)          capability matrix (frozen)
HB(P)                  execution semantics (frozen)
Score_3(P, D, HB, π)   CanonicalRealizationCost (frozen)
R(P, D)                this layer
argmin_{M ∈ R} Cost    later Search
```

v0.4.0 only defines the set. It must not pick `M*`.

---

## 2. What a realization is

A realization `M` is a reading of one S²C² program onto hardware
**without changing HB axioms**.

```text
M = (sched, spaceMap, device)
```

| Axis | Meaning | Already exists |
| ---- | ------- | -------------- |
| `sched` | one member of `ValidSchedules` | `cpu-seq` = `--s2c2-lower`; `gpu-async` / `npu-staged-dma` = token+concurrent+pipeline → async |
| `spaceMap` | logical `#stor.space` → target memref integers | `--convert-stor-to-memref=space-map=` |
| `device` | cost / capability profile | `--s2c2-cost-cp=device=cpu\|gpu\|npu\|cim` |

Source IR still owns residencies, engines, Concurrent vs Pipeline.
Those are part of `P` until a later rewrite pass is allowed to change
them **and** still prove `HB_source ⊆ HB_M`.

```text
R(P, D) = { M | IsLegal(P, D, M) ∧ HB_source ⊆ HB_M }
```

`π = Topo(G_HB; IRRank)` is **not** a member of `R`. It is determined
by `(P, HB)` for scoring one `M`. Search may later consider other
linear extensions; that is a different `M.sched` choice, not a change
to frozen v0.3.

---

## 3. Degrees of freedom

### Optimizer may *select* now (no IR rewrite)

```text
sched     ∈ { cpu-seq, gpu-async, npu-staged-dma }
spaceMap  ∈ target integer maps
device    ∈ { cpu, gpu, npu, cim }
```

These already produce distinct members of `R` for the X1 composition
program (`test/Conversion/capability-matrix.mlir`).

### Optimizer must not rewrite (would change semantics)

```text
Token / Concurrent / Pipeline axioms
HB = TC(PO ∪ SW ∪ StageOrder)
Object ≠ Residency
transfer = new residency + copy
Concurrent ≠ Pipeline
```

Turning Concurrent into Pipeline (or inventing sibling await) is
**not** a legal realization: it adds HB.

### Recorded rewrite axes (later, still not Search)

Only if a future pass proves `HB_source ⊆ HB_M` and `IsLegal`:

```text
residency placement (which Space for an object)
#comm.engine annotation
multi-hop SSD→DRAM→Device (already a Token chain, not a new construct)
```

Resource counts, queue depth, weighted matching, task-level duration
stay out of this layer.

---

## 4. Cost of a realization

For `M ∈ R(P, D)`:

```text
Cost(M) = Score_3(P, M.device, HB(P), π(P))
```

v0.3 still supplies the number. Different `device` profiles give
different scores for the **same** `P` (already K1 / H1 / C1). Different
`sched` / `spaceMap` are legality/lowering witnesses, not extra HB.

```text
Same P
  ├── M_cpu  = (cpu-seq, default map, cpu)     Cost = Score_3(·, cpu)
  ├── M_gpu  = (gpu-async, default map, gpu)   Cost = Score_3(·, gpu)
  └── M_map  = (cpu-seq, ssd=100,hbm=9, cpu)   legal space-map
```

No pass here enumerates `R` automatically.

---

## 5. Invariants

```text
Cost cannot add HB
π is canonical realization, not optimal schedule
Capability / device / space-map cannot change Token, Concurrent, Pipeline
R is a set of legal M; Search is argmin over that set
```

---

## 6. Out of scope

```text
search / placement / auto-scheduling / rewrite
arg min_M Cost(M)
changing v0.1 / v0.2 / v0.3 scores
redefining HB
StageResult / SoftPipe / iteration IR / race
resource counts / queue depth / weighted matching
IREE / StableHLO / MPI / CUDA / NPU ISA
```

---

## 7. Tests

Reuse existing files. No new lowering pass.

| ID | Claim |
| -- | ----- |
| R1 | X1 + `--s2c2-lower` ∈ `R` (cpu-seq), same as T1 |
| R2 | X1 + async triple ∈ `R` (gpu-async), same as T2; no sibling await |
| R3 | X1 + `space-map` ∈ `R`, same as T5 |
| R4 | same concurrent `P`: `Score_3(cpu) ≠ Score_3(gpu)` (C1 numbers) |
| R5 | Concurrent → Pipeline is **not** in `R` (would add StageOrder) |
| R6 | `π` is not a search choice; C9 keeps `G_full` a DAG under that π |
