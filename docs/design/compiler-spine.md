# S²C² Compiler Spine

**Status:** product lock. 6C-M / 7A / 7B merged. Semantic
Baseline v1 merged @ `b62bae4`. Apply contract frozen @
`038f4a1`. W0-3/2 inhabitant v0 is a host
([`ir-apply-inhabitant.md`](ir-apply-inhabitant.md);
`PR #141 — APPROVED` at `88764fb`; merge still gated).
Not an `F_storage_schedule` inhabitant. Not StableHLO.
`can-run-plan` stays no.

```text
Goal     name the five products and the only allowed mainline
Not      a new dialect, vendor, frontend, or generic scheduler
Rewrite  still closed at IR; 7B may name KEEP→EVICT→TRANSFER→RESTORE
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
6C-M   Sufficiency Decision           MERGED @ a0a2a08 (#136)
7A     Authorization Boundary         MERGED @ 5b57666 (#137)
7B     ONE storage rewrite            MERGED @ 3e942a8 (#138; plan)
Semantic Baseline v1                  MERGED @ b62bae4 (#140)
7B-Apply Controlled IR Apply          FROZEN @ 038f4a1 (#139; contract)
W0-3/2 Apply inhabitant v0            host; not can-run-plan; not Enum_F
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
Merged via `#136`.

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
Semantic freeze at `5b57666`. Merged via `#137`.

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
`rewrite-license=yes` does not transform IR. 7B names the
unique plan; `rewrite-path` stays `no`.

### 7B

[`storage-rewrite.md`](storage-rewrite.md).
Semantic freeze at `3e942a8`. Merged via `#138`.
IR apply stays closed. `#139` is unmerged contract.
Apply inhabitant stays CLOSED.

```text
rewrite-license  ≠  rewrite-plan
rewrite-plan     ≠  rewrite-path
```

One rewrite only:

```text
KEEP → EVICT → TRANSFER → RESTORE
```

`rewrite-plan=yes` names that sequence. It does **not**
apply it. `applied=no`. `rewrite-path=no`. Not ten
optimizations. Not an `F_storage_schedule` inhabitant.
Concurrent sibling reorder stays a frozen transform
witness; it is not this first product rewrite.

### Semantic Baseline v1

[`semantic-baseline-v1.md`](semantic-baseline-v1.md).
MERGED @ `b62bae4` via `#140`. Replays EA-1 / 6C-M 16-case /
7A 20-case / 7B 18-case / legacy RCE+XID. No new semantics.
Baseline PASS is a prerequisite, not apply authorization.

### 7B-Apply

[`ir-apply-contract.md`](ir-apply-contract.md)
(PR #139; FROZEN @ `038f4a1`; merged @ `2821de8`).
Route:
[`compiler-execution-spine.md`](compiler-execution-spine.md).
Host:
[`ir-apply-inhabitant.md`](ir-apply-inhabitant.md).

The contract page does not itself apply IR. The W0-3/2
host is one pattern: match, construct a candidate, check
`HB*` and an external witness, then commit or discard.
`can-run-plan` stays no. Failure leaves the source program
unchanged. Not `Enum_F`. Not Search. Acceptance anchor
`w0-3-2-storage-capacity-001`
(`runtime/record_apply_scenario.py`) replays that host.
It does not open a new cut.

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
