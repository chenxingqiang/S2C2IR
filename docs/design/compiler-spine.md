# S²C² Compiler Spine

**Status:** product lock. 6C-M / 7A / 7B merged. Semantic
Baseline v1 merged @ `b62bae4`. Apply contract frozen @
`038f4a1`. W0-3/2 inhabitant v0 is a host
([`ir-apply-inhabitant.md`](ir-apply-inhabitant.md);
merged @ `c19b356` via `#141`).
Not an `F_storage_schedule` inhabitant. Not StableHLO.
`can-run-plan` stays no. `next_cut` stays `NOT OPENED`.

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
#134   baseline citation              MERGED @ adda9d6; design-only
#135   F_storage_schedule design      MERGED @ c2d940f; design-only; no inhabitant
6C-M   Sufficiency Decision           MERGED @ a0a2a08 (#136)
7A     Authorization Boundary         MERGED @ 5b57666 (#137)
7B     ONE storage rewrite            MERGED @ 3e942a8 (#138; plan)
Semantic Baseline v1                  MERGED @ b62bae4 (#140)
7B-Apply Controlled IR Apply          FROZEN @ 038f4a1 (#139; contract)
W0-3/2 Apply inhabitant v0            MERGED @ c19b356 (#141); host; not can-run-plan; not Enum_F
Empirical Semantic Boundary v1        MERGED @ 3b31b79 (#145); evidence only
MLIR Carrier v0                       MERGED @ d328605 (#146) design, 87a782e (#147) text extract
Carrier handoff                       MERGED @ d8dc50f (#148); entry refusal @ 463c6b0 (#152)
Sealed stage                          MERGED @ ae88e42 (#144); evidence only
Host replay + CI                      MERGED @ ebc4cb6 (#158); check, not approval
7C     End-to-end executable opt      NOT OPENED
7D     CUDA backend realization       NOT OPENED
7E     Ascend backend realization     NOT OPENED
7F     CIM capability adapter         NOT OPENED
8A     StableHLO frontend             not before the spine runs
```

`7C` is not an engineering follow-up that opens by itself.
A proposal exists and is not opened:
[`cut-7c-proposal.md`](cut-7c-proposal.md). Its option A is an
orchestrator outside `s2c2-opt`, so the carrier stays
unregistered in `s2c2-opt` and the optimizer still does not
call `evaluate_apply`. The owner chose the reading in which the
orchestrator derives the host program from an IR file (A2).
Defining that mapping is a contract, so 7C would be a semantic
cut. It does not meet the written opening condition. The owner
also set the authorization rule for that cut: the most
efficient optimal strategy is the authorization. The frozen
hosts still do not derive authorization from a selection.
Opening is an explicit decision, not a documentation sync.

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
The 7B storage rewrite plan does not itself apply IR:
`rewrite-path=no` and `applied=no` remain unchanged.

The separate 7B-Apply contract is frozen and merged
(`038f4a1`, `2821de8`, `#139`). The W0-3/2 Apply inhabitant
v0 exists as a constrained host implementation (`c19b356`,
`#141`). It is not `Enum_F`, does not make
`can-run-plan=yes`, and does not open 7C. See 7B-Apply below.

The carrier is not registered in `s2c2-opt`, and the
optimizer does not call `evaluate_apply`.

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
It does not open a new cut. Scenario Corpus v1
([`scenario-corpus-v1.md`](scenario-corpus-v1.md))
replays ten scenes of that same host and pins a
behavior fingerprint. It does not change the contract.

### Empirical Semantic Boundary v1

[`empirical-semantic-boundary-v1.md`](empirical-semantic-boundary-v1.md).
Documentation checkpoint after the real-workload corpus.
Semantic baseline stays `36fd6fd`. This page does not
move it. Dialect, IR, and Apply are unchanged. Inside the
tested range, no `semantic_gap=true` was found.
OUTSIDE-CONTRACT is an inhabitant scope boundary.
The next cut stays closed until `stor`, `comp`, `comm`,
and `sched` cannot express a necessary relation.

### MLIR Carrier v0

[`mlir-carrier-v0.md`](mlir-carrier-v0.md).
Text extract is `runtime/record_mlir_carrier.py`.
The carrier is syntax for the host fields
`evaluate_apply` already reads. It is not a new
semantic model. `stor.transfer` is not the host
machinery step. TableGen stays absent. Lowering stays
closed. Semantic baseline stays `36fd6fd`.

### Compiler spine handoff

[`compiler-spine-integration.md`](compiler-spine-integration.md).
Host driver `runtime/record_compiler_spine.py`.
An opt flag is refused before extract. A text with no
single W0-3/2 region is refused before `evaluate_apply`.
The acceptance ApplyResult still comes from
`evaluate_apply`. `s2c2-opt` is not
invoked and has no carrier dialect. Lowering stays
closed. Semantic baseline stays `36fd6fd`.

### Workload mapping and adapter boundary

[`workload-mapping-v1.md`](workload-mapping-v1.md) is
evidence only: W1 EXPRESSIBLE, W2 and W3
OUTSIDE-CONTRACT, no cut proposed.
[`mlir-adapter-design-v0.md`](mlir-adapter-design-v0.md)
names which fields a carrier region determines and which
inputs stay outside that text. `device` and `induced-hb`
are external. They are not encoded by the carrier, and
they are not decided by extract. This page does not add
an extract, a dialect, or a rewrite. The next cut stays
closed.

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
