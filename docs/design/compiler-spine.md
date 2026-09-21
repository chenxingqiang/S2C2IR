# S²C² Compiler Spine

**Status:** product lock. 6C-M frozen. 7A opened as a
query boundary. Not a rewrite. Not an
`F_storage_schedule` inhabitant. Not StableHLO.

```text
Goal     name the five products and the only allowed mainline
Not      a new dialect, vendor, frontend, or generic scheduler
Rewrite  still closed; 7A may emit authorized / rewrite-license Decisions
```

This page is the engineering constitution after the
architecture-research phase. Semantic IR, Evidence,
Capability, Realization, Checking, Search, and Transform
already have frozen boundaries. The remaining work is one
executable optimization spine, not more design surface.

```text
architecture semantics    near-complete
engineering productization  the gap
```

Do **not** change healthcheck scores here. Those stay on
[`architecture-healthcheck.md`](architecture-healthcheck.md).

## Five products

```text
                    S²C² Compiler
                         │
        ┌────────────────┼────────────────┐
        │                │                │
     Semantic         Evidence         Hardware
        │                │                │
        └───────────────┬┴────────────────┘
                        ↓
                 Realization Engine
                        ↓
               Schedule / Transform
                        ↓
                   Backend
```

| Product | Answers | Status |
| ------- | ------- | ------ |
| Semantic IR | What is stored, computed, moved, ordered? | FROZEN `stor/comp/comm/sched` |
| Evidence / Capability | What can this device do, under which evidence? | FROZEN |
| Realization | \(R(P,D)=\{M\mid IsLegal(P,D,M)\land HB_M=HB_{source}\}\) | FROZEN |
| Optimization | Candidate → legality → sufficiency → select → authorize → transform | MAINLINE |
| Backend | Realization → lowering → runtime / kernel | LATER carrier only |

Backend must not redefine S²C² semantics.

## Optimization is not an IR pass soup

```text
Candidate
   ↓
Legality
   ↓
Sufficiency
   ↓
Cost / Measurement
   ↓
Selection
   ↓
Authorization
   ↓
Transform
   ↓
HB / Legality verification
```

Optimization operates on Realization / Candidate, not by
directly mutating IR from a cost heuristic.

```text
F  →  Legal  →  sufficient  →  cost  →  argmin/Pareto
   →  authorization  →  transform
```

Never:

```text
F  →  argmin  →  rewrite
```

## Mainline

```text
#134   baseline citation              design-only; merge gated
#135   F_storage_schedule design      design-only; no inhabitant
6C-M   Sufficiency Decision           FROZEN @ a0a2a08 (#136)
7A     Authorization Boundary         opened this wave
7B     ONE storage rewrite            CLOSED
7C     End-to-end executable opt
7D     CUDA backend realization
7E     Ascend backend realization
7F     CIM capability adapter
8A     StableHLO frontend             not before the spine runs
```

`#134` / `#135` stay drafts until the exact review token
`PR #N — APPROVED`. This page does not merge them.

### 6C-M

[`storage-capacity-sufficient.md`](storage-capacity-sufficient.md).

```text
Decision.subject = sufficient
```

is a first-class Decision, produced by
`SufficiencyEvaluator` over independent required
predicates. It is **not**

```text
usable ∧ applicable ⇒ sufficient
```

and **not** a new boolean on the 6C-I license printer.

### 7A

[`authorization-boundary.md`](authorization-boundary.md).

```text
sufficient  ≠  authorized
authorized  ≠  rewrite-license
```

```text
Can the realization work?          sufficient
Is this action permitted?          authorized
May the compiler change IR?        rewrite-license
```

`AuthorizationIdentity = (selected, object, action)`.
v0.1 action is `storage-rewrite` (named, not implemented).
Policy v0.1 is not `if sufficient: authorized = yes`.

### 7B (closed)

One rewrite only:

```text
KEEP → EVICT → TRANSFER → RESTORE
```

Not ten optimizations. Concurrent sibling reorder stays a
frozen transform witness; it is not this first product
rewrite.

## Do not expand sideways

```text
StableHLO / PyTorch / JAX
more operators
CUDA + ROCm + Ascend + CIM + runtime + generic scheduler
```

in parallel. That produces a framework that connects
everything and closes nothing.

CIM is a `CapabilityProfile` + Evidence + Realization.
It is **not** a `cim.*` dialect.

Frontend later:

```text
handwritten S²C² workload
        ↓
semantic normalize
        ↓
capacity / realization / optimization
        ↓
backend
```

then, only after that spine runs:

```text
PyTorch / JAX → StableHLO → S²C²
```

## Frozen (do not reopen)

```text
stor / comp / comm / sched
Token / Concurrent / Pipeline
HB definition
Realization Space
Cost v0.1–v0.3
Search contract / Neighbor / Start / Restart
Transform semantics
EvidenceRecord identity
Capability identity
Decision subject model
6C-J / 6C-K / 6C-L occupancy kinds
EA-1 Decision.subject=usable printer
```

Do not mix:

```text
HB_M = HB_source          realization membership
HB_source ⊆ HB_impl       implementation correctness
```

## Out of scope (this page)

```text
IR replace / erase / applySchedule
F_storage_schedule inhabitant
StableHLO
new capability kinds
new vendors
generic schema validator
expanding S2C2CapabilitySchedule.cpp
changing architecture-healthcheck.md scores
```
