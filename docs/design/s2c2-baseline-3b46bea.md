# S²C²IR citable baseline — `3b46bea`

**Commit:** `3b46bea`  
**Parents:** `d953ee1` (#81 stack promotion) + `2fa4dfd` (#133)  
**Status:** citation package. No new semantics.

```text
3b46bea is on main.
FACT/CHECKING compose and Search_F companion are in-tree.
```

## Chain

```text
Evidence
  -> Predicate
  -> usable / applicable
  -> Independent Report
  -> Capability Profile          s2c2.capability_profile.v1
  -> Realization Legality        s2c2.realization_legality.v1
  -> Realization Claim           s2c2.realization_claim.v1
  -> Per-kind Checking           s2c2.realization_checking.v1
  -> E2E compose (cuda/4090)
  -> Cross-identity (cuda/ascend/cpu)
  -> STOP
```

Checking is Claim × Legality Fact per-kind compatibility.
It is not “can this realization run”.

```text
r = (D, K_r)
L = (D, {k |-> c_k})
Check(r,L) = {(k, f(c_k), c_k) | k in K_r}
```

```text
allowed         -> satisfy
forbidden       -> violate
not-applicable  -> violate
unproven        -> unproven
```

Search on this baseline:

```text
Search_F(Policy) = Policy(Enum_F) ⊆ Enum_F
--s2c2-argmin already is Search_F(ArgMin) / Search_F(Pareto)
Numbered v0.4.5 remains Search Space / Neighbor / Legality
```

## Citation sentence

> S²C²IR separates semantic requirements from hardware
> realization constraints, and makes the boundary between
> evidence, legality, and realization explicitly analyzable.

中文：S²C²IR 将程序语义要求与硬件实现约束解耦，并将
Evidence、Legality 与 Realization 之间的边界显式化、可分析化。

Do not cite Checking as “validates a concrete hardware
realization.”

## Replay (hosts already in-tree)

```bash
git checkout 3b46bea
python3 runtime/record_realization_checking.py --print-realization-checking-contract
python3 runtime/record_realization_checking_e2e.py --print-realization-checking-e2e-matrix
python3 runtime/record_realization_checking_xid.py --print-realization-checking-xid-matrix
```

No GPU. No `s2c2-opt`. Do not FileCheck microseconds.
This environment lands on host `_validate()` + FileCheck simulation.

## CLOSED

```text
sufficient / Decision.subject=sufficient / 6C-M
can-run-plan=yes
authorization.* / rewrite-license=yes
F_storage_schedule implementation
generic schema validator
invented npu/cim catalog cells
leftover PRs #18 #28 #43 #50 #52 #59 #64 #65 #67 #121
```
