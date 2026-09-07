# Search / Pareto over R (v0.4.1)

Status: **v0.4.1 frozen**. Selects among already-legal realizations.
Does not rewrite IR, place residencies, or redefine Token /
Concurrent / Pipeline. Realization Space v0.4.0 and Cost v0.1–v0.3
remain frozen.

```text
v0.4.0  R(P, D)                                FROZEN
v0.4.1  Search / Pareto over R                 FROZEN (this document)
v0.4.2  Realization Enumerator                 FROZEN in realization-enumerator.md
v0.4.3  listing pass `--s2c2-enumerate`        FROZEN in realization-enumerator-pass.md
v0.4.4  listing `--s2c2-argmin`                FROZEN in realization-argmin-pass.md
v0.4.5  Search Space / Neighbor / Legality     in search-space.md
v0.4.6  Search Algorithm Contract              in search-algorithm-contract.md
v0.4.7  StartPolicy / RestartPolicy            in search-start-policy.md
v0.4.8  Algorithm = (N, S, Rst, Nxt, Acc)      in search-algorithm.md
v0.4.9+ Hamming-1 walk / later algorithms      later
```

```text
Search ≠ Rewrite
Search ≠ HB
Search ≠ π
CanonicalRealizationCost ≠ Optimization
M ≠ π
HB_M = HB_source                           semantic realization
HB_source ⊆ HB_impl                        lowering correctness
```

---

## 1. Domain (frozen)

```text
R(P, D) = { M | IsLegal(P, D, M) ∧ HB_M = HB_source }
M       = (sched, spaceMap, device)
```

`HB_source` means `HB(P)`. Search may only read this set. It must not
grow `R` by adding HB (Concurrent → Pipeline is already ∉ `R`).

```text
Frozen Semantics
       ↓
HB(P)
       ↓
IsLegal(P, D, M)
       ↓
HB_M = HB(P)
       ↓
M ∈ R(P, D)
       ↓
Cost(M) = Score_3(P, M.device, HB(P), π(P))
       ↓
M* or Pareto(R)                            this layer
```

---

## 2. What Search is allowed to choose

Already-selectable axes, no IR rewrite:

```text
sched     ∈ { cpu-seq, gpu-async, npu-staged-dma }
spaceMap  ∈ already-legal target integer maps
device    ∈ { cpu, gpu, npu, cim }
```

subject to `IsLegal` and `HB_M = HB_source`.

```text
π = Topo(G_HB; IRRank)
```

is **not** a search variable. It is determined by `(P, HB)` for scoring
one `M`. Treating other linear extensions as decisions would reopen
v0.3.

---

## 3. Objectives (existing Score_3 only)

v0.3 already prints, and this layer reuses, per `M.device`:

```text
T_HB           critical_path
C_contention   contention
C_capacity     capacity
Score_3.total  T_full + C_capacity
               = T_HB + C_contention + C_capacity
```

No new weights, durations, queues, or device tables.

### Scalar search

```text
ArgMin(P, D) = argmin_{M ∈ R(P, D)} Score_3(M).total
ArgMin(P, D) ⊆ R(P, D)
```

`ArgMin` is a **set**. If several `M` share the same total, all of
them are minima. Do not break the tie by adding HB, inventing a
lexical IR rule, or changing `π`. `M*` denotes any member of
`ArgMin(P, D)`.

### Pareto search

```text
Cost⃗(M) = (T_HB, C_contention, C_capacity)
Pareto(R) = { M ∈ R | no M' ∈ R strictly dominates M }
```

`M'` strictly dominates `M` when every component is `≤` and at least
one is `<`. Scalar `total` is the sum of the three components, not a
fourth independent objective.

---

## 4. Honest dependence of Cost on M

Frozen v0.3 Cost is

```text
Cost(M) = Score_3(P, M.device, HB(P), π(P))
```

`sched` and `spaceMap` are members of `M` and of `R`. They do **not**
currently change the number. Therefore `argmin` / Pareto over today's
`R` partitions by **device** (and by legality of that device). Distinct
`sched` / `spaceMap` at the same device are ties.

That is not a defect of Search. Making Cost depend on `sched` or
`spaceMap` would be a new Cost revision, which this document does not
open.

---

## 5. What this layer must not do

```text
rewrite Token / Concurrent / Pipeline
add StageOrder or sibling await
treat π as a schedule to optimize
change v0.1 / v0.2 / v0.3 scores
weighted matching / queue depth / task-level duration
residency placement rewrite
auto-scheduling IR
IREE / StableHLO / MPI / CUDA / NPU ISA
```

A later enumerator may print `M*` / `Pareto(R)` on stderr. It must not
rewrite `P`.

---

## 6. Tests

Reuse existing scores. No new Cost pass.

| ID | Claim |
| -- | ----- |
| S1 | R4 / C1 with `D_test={cpu,gpu}`: `Score_3(gpu).total=128 < Score_3(cpu).total=136` ⇒ every scalar minimum in `R_test` uses `device=gpu` |
| S2 | C6 / C9 with `D_test={cpu,gpu}`: equal totals ⇒ both are scalar minima of `R_test` |
| S3 | Concurrent → Pipeline is not in the search domain (`∉ R`) |
| S4 | `π` is not enumerated; C9 still uses canonical topo |
| S5 | GPU weakly dominates CPU on C1's `Cost⃗` (same `T_HB` / capacity, less contention); that is a device-table fact, not a semantic law |
| S6 | `cpu-seq` and `gpu-async` remain distinct legal `M` for the same `P` even when they tie on Score_3 |
