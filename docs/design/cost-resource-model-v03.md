# Cost Model v0.3: critical-path resource cost

Status: **v0.3 frozen**. Score-only CanonicalRealizationCost. Does not
search, place, or rewrite. Does not redefine Token / Concurrent /
Pipeline. v0.1 and v0.2 remain frozen.

```text
v0.1  Cost(IR, Device)                         syntax heuristic          FROZEN
v0.2  Cost(S²C², Hardware, HB, Mapping)        pair credit − overlap     FROZEN
v0.3  CanonicalRealizationCost                 FROZEN (this document)
v0.4.0 Realization Space R(P, D)               FROZEN in realization-space.md
v0.4.1 Search / Pareto over R                  FROZEN in search-pareto.md
v0.4.2 Realization Enumerator                  FROZEN in realization-enumerator.md
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

Layers stay separate:

```text
Semantics  →  Legality  →  Cost  →  Optimization
   frozen       frozen     v0.3      later Search
```

v0.2 itself is not revised. Its credit

```text
C_overlap = min(Σ eligible compute, Σ eligible communication)
```

is self-consistent **only while** the GPU/NPU matrix is the current
complete off-diagonal (“unlike kinds may overlap”). That bound is
frozen with v0.2. A later sparse or weighted matrix would need

```text
C_overlap* = max Σ x_ij · credit_ij
             s.t. x_ij ≤ Candidate(i,j)
             plus resource capacity / duration
```

That matching problem is **not** v0.3 and is **not** Search. v0.3
stops stacking overlap credit and scores a path instead.

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
G_HB     = frozen HB edges     (must be a DAG)
π        = CanonicalTopo(G_HB; IR-rank tie-break)
           A →HB B  ⇒  π(A) < π(B)
G_conflict:
    A ↛HB B ∧ B ↛HB A
    ∧ ¬OverlapCapability(kind(A), kind(B))
    ∧ π(A) < π(B)
        ⇒  add score-only edge A → B
G_full   = (V, E_HB ∪ E_conflict)     (still a DAG)
```

`π` is **CanonicalRealizationCost**, not OptimalScheduleCost. IR rank
is only the tie-break among HB-ready nodes (Kahn). Pairwise IR order
is **not assumed** to be an HB-consistent linear extension.
Canonical topological ordering makes that property explicit and
guarantees that added conflict edges preserve DAG-ness.

Current S²C² SSA (PO / SW dominance / StageOrder) may already make
`G_HB` compatible with lexical IR order. That is **not proven** here,
so the pass does not rely on it. C9 does **not** claim the old
pairwise IR-order rule would cycle; it only checks that the canonical
orientation stays a DAG under reverse-looking SW plus unordered IO.

A cyclic `G_HB` or `G_full` is a pass failure, not a silent score.

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

Research target for this layer:

```text
HB Graph
  + Resource Capacity
  + Task Duration
  + Critical Path
  + Storage / Communication contention
        ↓
Estimated Schedule Cost     (still a score)
```

This cut implements path length now, and records the rest:

| Piece | v0.3.0 |
| ----- | ------ |
| Frozen HB | used as `G_HB` |
| Critical path | `T_HB` / `T_full` |
| Communication contention | `G_conflict` along `π` |
| Storage capacity | `C_capacity = C_storage` |
| Task duration | **leaf ticks**; not aggregated per `sched.task` |
| Resource counts / queues | recorded, coefficient 0 |

Leaf timing answers “which work units sit on the path?” Task-level
demand stays a Cost refinement, not a Search pass.

```text
v0.3.0  leaf durations + HB + pairwise conflict + storage occupancy
later   Task Duration / resource counts
later   Search / Placement / Auto-Scheduling
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
replacing v0.2 min(ΣC, ΣM) with weighted matching
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
| C9 | reverse-looking SW + unordered IO: canonical orientation keeps `G_full` a DAG |
