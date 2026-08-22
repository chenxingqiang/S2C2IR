# Cost Model v0.2: HB-aware resource cost

Status: **design + score-only analysis**. Does not search, place, or
rewrite. Does not redefine Token / Concurrent / Pipeline. v0.1 remains
frozen ([`cost-resource-model.md`](cost-resource-model.md)).

```text
v0.1  Cost(IR, Device)                         syntax-construct heuristic
v0.2  Cost(S²C², Hardware, HB, Mapping)        HB-filtered + resource-pair capability
v0.3+ search / placement                       later
```

`Mapping` in v0.2 is the existing device / capability profile
(`device=cpu|gpu|npu|cim`), not a search over placements. Search stays
v0.3+.

```text
Lowering_target may realize HB, but must not redefine HB
CostModel ≠ ExecutionSemantics
```

---

## 1. What changes

v0.1 credits `min(Σ compute, Σ communication)` for a whole
`sched.concurrent` / `sched.overlap` when `canOverlap=true`. An explicit
cross-sibling `wait` still got the group credit.

v0.2 keeps the same leaf ticks (`C_compute`, `C_storage`,
`C_communication`, `C_synchronization`) and the same formula

```text
Cost = C_compute + C_storage + C_communication + C_synchronization
       − C_overlap
```

but overlap credit is:

```text
OverlapCandidate(A, B)
    iff  A ↛HB B  ∧  B ↛HB A
    and  OverlapCapability(kind(A), kind(B))
```

```text
Concurrent
    → Frozen HB Graph          (PO ∪ SW ∪ StageOrder; no sibling PO)
    → drop pairs already ordered by HB
    → candidate pairs
    → resource capability
    → upper-bound credit
```

`C_overlap` is still an **upper-bound credit**, not predicted runtime.
Pipeline `StageOrder` still contributes **no** inter-stage credit.

---

## 2. Resource kinds

| Kind | IR |
| ---- | -- |
| Compute | `comp.elemwise` / `matmul` / `gated_mlp` |
| DMA | `comm.stream` with `#comm.engine<dma>` and neither end is SSD/Host |
| IO | `stream` / `copy` / `transfer` whose src or dst space is `ssd` or `host` |
| Comm | other `pack` / `copy` / `stream` / `transfer` movement |

SSD/Host wins over the DMA engine tag: an SSD DMA stream is **IO**.

---

## 3. OverlapCapability matrix (v0.2)

`canOverlap : bool` stays on v0.1 only. v0.2 uses a symmetric 4×4
matrix. Diagonal is 0 (same-kind pairs get no credit).

CPU and CIM: all entries 0.

GPU and NPU:

```text
              Compute   DMA   Comm   IO
Compute          0       1     1      1
DMA              1       0     1      1
Comm             1       1     0      1
IO               1       1     1      0
```

So two concurrent SSD streams (IO∥IO) get **no** credit even without HB.

---

## 4. Credit

Collect movement/compute **work items** (leaves with compute or
communication ticks) inside a concurrent / overlap region. Storage and
wait ticks are never paired.

```text
eligible(A)  =  ∃ B. OverlapCandidate(A, B)
C_overlap    =  min( Σ compute of eligible items,
                     Σ communication of eligible items )
```

Still capped by the region’s total compute/communication. Cross-sibling
`wait event(T1)` in T2 makes T1’s actions →HB T2’s later actions, so
those pairs are not candidates.

Pass: `--s2c2-cost-hb=device=cpu|gpu|npu|cim`  
`--s2c2-cost` is unchanged (v0.1).

Print:

```text
s2c2-cost-hb device=gpu func=k5 compute=… storage=… communication=… synchronization=… overlap=… total=…
```

---

## 5. Out of scope

```text
search / placement / auto-scheduling
changing v0.1 scores
redefining HB
StageResult / SoftPipe / iteration IR / race analysis
IREE / StableHLO / MPI
```

---

## 6. Tests

| ID | Claim |
| -- | ----- |
| H1 | same as K1: GPU `overlap>0` (Compute∥IO, no HB) |
| H2 | sequential: `overlap=0` |
| H3 | pipeline stages: GPU `overlap=0` |
| H5 | concurrent compute + `wait` + comm: GPU `overlap=0` (HB removes the pair) |
| H5′ | same IR under frozen `--s2c2-cost`: GPU still `overlap=1` (v0.1 does not walk HB) |
| H6 | two concurrent IO streams, no wait: GPU `overlap=0` (IO∥IO = 0) |
