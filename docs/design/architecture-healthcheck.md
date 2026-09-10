# Architecture Health Check (after 6C-I)

**Status:** FROZEN diagnosis. Taken at 6C-I
([PR #116](https://github.com/chenxingqiang/S2C2IR/pull/116)).
Not a rewrite. Not a new \(F\). Not a hardware campaign.
Not a production frontend.

```text
Goal     freeze what the architecture has proven, and what it has not
Not      F_storage_schedule implementation, eviction rewrite, or vendor expansion
Rewrite  still only from an existing capability license
```

After 6C-I the identifiable product is:

```text
S²C²
  = Semantic Execution IR
  + Storage Hierarchy
  + Evidence-Bounded Scheduling
```

That is **not** “a large-model compiler” and **not** “a GPU
optimizer”. Storage is a first-class execution concern, not a
backend memcpy detail.

The framework can correctly **express** and **cautiously
select**. It has **not** shown that it stably finds better
schedules than mature systems on a wide real-workload set.

Overall architecture score: **7.5/10**. That number is the
gap between IR/semantics/evidence and search/cost/capacity
generalization. It is not a claim that the IR is immature.

## Proven strengths (do not regress)

```text
Storage + Comm + Compute + Execution Semantics
Semantic dependency          ≠  performance serialization
Unknown                      →  Preserve
capability classification    ≠  rewrite authorization
IR semantics                 ≠  hardware realization
same IR + 4090 evidence      →  realization A
same IR + 910B evidence      →  realization B
F(site) → F(chain) → F(program) → F_capacity
selected                     ≠  rewrite
F_capacity                   ⊆  F_residency
LiveTiles(t)                 ≠  LiveBytes(t)
closed=yes                   ≠  sufficient
source-data=yes              ≠  rewrite-license=yes
measurement                  ≠  an expanded F
```

Evidence-bounded pipeline (unchanged):

```text
Measurement
   ↓
Evidence
   ↓
Applicability
   ↓
Candidate legality F
   ↓
Policy selection
   ↓
Rewrite license
   ↓
Rewrite
```

4090 / 910B proved **portable realization under evidence**,
not workload-breadth superiority.

## Current shape: evaluator, not search engine

The compiler is strong at **ranking a given legal set**.
It is not yet a general schedule search engine. The four
gaps are still separate:

| Gap | What exists now |
| --- | --------------- |
| Candidate generation | Hand-designed finite sets: PREFETCH/PRESERVE, KEEP/TRANSFER, KEEP/EVICT |
| Cost | `cost-v04` structural ticks + scoped `measured-*-v1`; not a unified performance model |
| Capacity | tile-count occupancy (`size=1`, `peak-live=3`, `capacity=2`); not `LiveBytes(t)` / allocator / alias |
| Alias / mutation / validity | unknown → no rewrite; safe, and many opportunities stay closed |

Pipeline depth, residency lifetime, capacity, and transfer
overlap are **separate capabilities**. They are not one
joint candidate family.

## Scores (engineering architecture, not paper completeness)

| Dimension | Score |
| --------- | ----: |
| IR architecture | 9/10 |
| Execution semantics | 9.5/10 |
| Storage modeling | 9/10 |
| Evidence discipline | 9.5/10 |
| Hardware adaptation | 8/10 |
| Candidate scheduling | 7.5/10 |
| Cost model | 5.5/10 |
| Capacity modeling | 5/10 |
| Alias / lifetime analysis | 5/10 |
| Production frontend | 3/10 |
| Real-world workload breadth | 5/10 |
| **Overall** | **7.5/10** |

## Do not do next

```text
replace / erase IR
rewrite-license=yes
closed=yes or source-data=yes as a license
tile occupancy pretending to be a byte allocator
cost-v04 promoted to a real performance model
PyTorch / ONNX / StableHLO frontend
AMD / CPU / CIM / extra vendor campaigns
re-measuring 5A–5D
opening 5E
flattening C||Storage
invented sibling sched.wait
FileCheck of microseconds
changing cost-v04 / default-3g / #69 / Evidence DB identity
```

Frontend and vendor breadth would turn the project back into
a benchmark or ingestion tree. Architecture thickness comes
first.

## Agreed cut sequence

Finish the EVICT **sufficient** contracts one conjunct at a
time. Then freeze a joint candidate family. License and
rewrite stay after both.

```text
6C-J   source-data validity          query-only; still sufficient=no
6C-K   restore ordering              still sufficient=no
6C-L   dest invalidation             still sufficient=no
       F_storage_schedule design     prefetch × depth × residency × capacity
                                     still no rewrite
       measured evidence
          ↓
       ArgMin
          ↓
       license
          ↓
       rewrite
```

`F_storage_schedule` is the later opportunity, not the next
implementation cut. Opening it now would mix candidate
generation, joint cost, byte-level capacity, and
alias/validity into one PR and blur the 6C-B–I freeze.

Target family (design only, not this document’s
implementation):

```text
F_capacity
   ↓
F_storage_schedule
        prefetch distance
        buffer depth
        residency lifetime
        eviction / restore
        pipeline overlap
```

That family reuses Evidence / Applicability / \(F\) / policy /
license. It does **not** reopen 4C, 5A–6B, or 6C-B–I.

## Out of scope (this freeze)

```text
implementing F_storage_schedule
opening 6C-K / 6C-L in this document
merging a source-data PR by this freeze
rewrite-license=yes
IR replace / erase
production frontend
new hardware campaign
```
