# Baseline E2E Integration v0

**Status:** integration / reproducibility from `e969ae8`.
**Semantic expansion:** none.
Not a rewrite. Not `sufficient=yes`. Not can-run-plan.
Does not modify Profile, Legality, or Checking result
semantics. Does not expand `S2C2CapabilitySchedule.cpp`.

```text
Goal     replay Evidence records → Profile → Legality → Claim → Check
         through frozen hosts, deterministically
Not      a new result enum, plan, occupancy, Predicate re-run, or rewrite
```

```text
BASELINE = e969ae8
TYPE     = integration / reproducibility
SEMANTIC EXPANSION = NONE
```

#130 is a host `Check(r, L)`. This cut only **composes**
that host with the frozen Profile and Legality hosts.

```text
capability records     (existing EvidenceRecord factory)
   ↓
derive_capability_profile
   ↓
derive_realization_legality
   ↓
s2c2.realization_claim.v1
   ↓
check_realization          ← only place result mapping lives
   ↓
per-kind findings
   ↓
STOP
```

`Check_E2E(r, L) == Check_v0(r, L)`. The harness does not
contain `allowed → satisfy`.

## Cases

| Case | Records | Claim | Check |
| --- | --- | --- | --- |
| legal-claim | pair yes | `[staged-dma, concurrent-pair]` | pair `satisfy`+`allowed`; dma `unproven`+`unproven` |
| unsatisfied-claim | pair no, dma yes | same | pair `violate`+`forbidden`; dma `satisfy`+`allowed` |
| identity-mismatch | pair yes | other device | `contract-error`; `findings=[]` |

Unclaimed `named-nonblocking` produces no finding.

## Forbidden

```text
new capability kinds
modify Profile / Legality / Checking semantics
IR witness / plan / occupancy / schedule
sufficient / can-run-plan=yes
authorization.* / rewrite
s2c2-opt consuming Checking
S2C2CapabilitySchedule.cpp
FileCheck of microseconds
```

## Host contract

```bash
python3 runtime/record_realization_checking_e2e.py --print-realization-checking-e2e-contract
python3 runtime/record_realization_checking_e2e.py --print-realization-checking-e2e-matrix
```

Query-only. `can-run-plan=no`. `rewrite-license=no`.
