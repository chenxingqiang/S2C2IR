# Cost Model v0.3: critical-path resource cost

Status: **design + score-only analysis**. Does not search, place, or
rewrite. Does not redefine Token / Concurrent / Pipeline. v0.1 and v0.2
remain frozen.

```text
v0.1  Cost(IR, Device)                         syntax heuristic          FROZEN
v0.2  Cost(S²C², Hardware, HB, Mapping)        pair credit − overlap     FROZEN
v0.3  CriticalPath(HB) + Contention + Capacity this document
v0.4+ search / placement / auto-scheduling     later
```

```text
Lowering_target may realize HB, but must not redefine HB
CostModel ≠ ExecutionSemantics
Score ≠ LatencyPrediction
```

`Mapping` is still the device / capability profile
(`device=cpu|gpu|npu|cim`), not a search over placements.

---

## 1. Why v0.2 stops here

v0.2 is **pair-unordered + resource-compatible** credit:

```text
C_overlap = min(Σ eligible compute, Σ eligible communication)
```

That is still an upper-bound *group* credit, not a schedule length. It
does not use:

```text
task durations
other dependencies on the same path
resource contention beyond a pairwise bit
critical path
multiple DMA queues
```

So `A || B || C` can be optimistic (two sibling `{compute; comm}`
chains) or pessimistic (Compute || DMA || IO lumped as one comm pool).

v0.3 **does not stack more overlap credit**. It replaces the
sum-minus-credit total with:

```text
Cost = T_critical_path(HB)
     + C_contention
     + C_capacity
```

Still a **score**. Not predicted runtime, not a scheduler.

---

## 2. Timed leaves (unchanged ticks)

Same leaf ticks as v0.1 / v0.2. Storage is **not** a path duration.

| Leaf | Duration on the path | Elsewhere |
| ---- | -------------------- | --------- |
| compute (`elemwise` / `matmul` / `gated_mlp`) | `C_compute` | — |
| move (`pack` / `copy` / `stream` / `transfer` copy) | `C_communication` | — |
| `wait` / `barrier` | `C_synchronization` | — |
| `materialize` / `alloc` / `transfer` dest | 0 | `C_capacity` |

HB walk is the same as `--check-s2c2-execution` / `--s2c2-cost-hb`:
`TC(PO ∪ SW ∪ StageOrder)`, no sibling PO.

---

## 3. Constraint graphs

```text
G_HB        = frozen HB edges
G_conflict  = for work items A, B (compute/move leaves):
                A ↛HB B ∧ B ↛HB A
                ∧ ¬OverlapCapability(kind(A), kind(B))
              add a score-only edge earlier → later in IR walk order
G           = G_HB ∪ G_conflict
```

IR order is a **canonical serialization** for incompatible unordered
pairs. It is not placement search and does not pick a better order.

```text
T_HB   = longest path of durations on G_HB
T_full = longest path of durations on G
```

```text
C_contention = T_full − T_HB
C_capacity   = C_storage          (same bytes × 1 tick as v0.2)
Cost         = T_full + C_capacity
```

`C_capacity` is occupancy / allocation pressure, not path time.
Communication *queue depth* and multi-channel bandwidth sharing stay
recorded, coefficient 0 in v0.3.

OverlapCapability matrix is **unchanged** from v0.2 (GPU/NPU 4×4,
CPU/CIM all 0, SSD/Host ⇒ IO).

---

## 4. Granularity

v0.3 still times **leaf operations**, then constrains them with HB and
pairwise resource conflicts. That matches the recorded v0.2 follow-up:
task-level resource demand is later, once this layer is a scheduler
input rather than a score.

```text
v0.3  leaf durations + HB + pairwise conflict edges
later Task-level resource demand
later resource counts / queue depth
later Search
```

---

## 5. Pass

```text
--s2c2-cost-cp=device=cpu|gpu|npu|cim
```

Does not change `--s2c2-cost` or `--s2c2-cost-hb`.

```text
s2c2-cost-cp device=gpu func=c1 critical_path=… contention=… capacity=… total=…
```

`critical_path` prints `T_HB` (HB-only). `total = T_full + capacity`.

---

## 6. Out of scope

```text
search / placement / auto-scheduling / rewrite
changing v0.1 or v0.2 scores
redefining HB
cycle-accurate latency
queue depth / multi-channel / NoC
StageResult / SoftPipe / race
IREE / StableHLO / MPI
```

---

## 7. Tests

| ID | Claim |
| -- | ----- |
| C1 | Compute∥IO, no HB: GPU `contention=0` (pair capable) |
| C2 | sequential: `contention=0` |
| C3 | pipeline: StageOrder already in `T_HB`, `contention=0` |
| C5 | wait sibling: SW already in `T_HB`, GPU `contention=0` |
| C6 | two IO streams: GPU `contention>0` (IO∥IO serializes) |
| C7 | two sibling `{compute; IO}` chains: v0.2 pair credit is optimistic vs `T_full` |
| C8 | Compute∥DMA∥IO: v0.2 lumps DMA+IO as one comm pool; `T_HB = max` of three |
