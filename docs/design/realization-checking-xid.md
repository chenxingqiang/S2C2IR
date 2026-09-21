# Cross-identity Checking E2E v0

**Status:** integration / reproducibility from `e969ae8`.
**Semantic expansion:** none.
Not a rewrite. Not `sufficient=yes`. Not can-run-plan.
Does not modify Profile, Legality, or Checking result
semantics. Does not expand `S2C2CapabilitySchedule.cpp`.
Does not invent `npu` / `cim` catalog cells.

```text
Goal     replay Check(r, L) on frozen cuda / ascend / cpu
         identities through the same hosts
Not      a new result enum, plan, occupancy, or rewrite
```

```text
BASELINE = e969ae8
TYPE     = integration / reproducibility
SEMANTIC EXPANSION = NONE
```

#130 is a host `Check(r, L)`. This cut only **composes**
that host on identities already present in CAPA:

```text
cuda   / sm89:rtx4090
ascend / ascend910b
cpu    / host
```

```text
capability records     (existing EvidenceRecord factory)
   ↓
derive_capability_profile(target, device)
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

`Check_XID(r, L) == Check_v0(r, L)`. The harness does not
contain `allowed → satisfy`. Cross-target identity
mismatch is `contract-error`, not a legality result.

## Cases

| Case | Identity | Records | Claim | Check |
| --- | --- | --- | --- | --- |
| cuda-legal | cuda / 4090 | pair yes | `[staged-dma, concurrent-pair]` | pair `satisfy`+`allowed`; dma `unproven`+`unproven` |
| ascend-dma | ascend / 910B | dma yes | same kinds | pair `unproven`+`unproven`; dma `satisfy`+`allowed` |
| cpu-na | cpu / host | pair n/a | `[concurrent-pair]` | pair `violate`+`not-applicable` |
| cross-target | L=ascend; r=cuda | dma yes | cuda pair | `contract-error`; `findings=[]` |

Unclaimed `named-nonblocking` produces no finding.
`npu` / `cim` device strings are not introduced.

## Forbidden

```text
new capability kinds
invented npu / cim catalog cells
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
python3 runtime/record_realization_checking_xid.py --print-realization-checking-xid-contract
python3 runtime/record_realization_checking_xid.py --print-realization-checking-xid-matrix
```

Query-only. `can-run-plan=no`. `rewrite-license=no`.
