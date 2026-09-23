# W0-3/2 Apply Inhabitant v0

**Status:** host for the frozen IR Apply Contract v0.1
(`038f4a1`, merged @ `2821de8`). Review head `88764fb`
(`PR #141 — APPROVED`; merge still gated). One pattern.
Not a generic rewrite engine. Not `Enum_F`. Not Search.
Not authorization. `can-run-plan` stays no.

Parent contract: [`ir-apply-contract.md`](ir-apply-contract.md).
Does not edit `record_sufficiency.py`,
`record_authorization.py`, or `record_storage_rewrite.py`.

```text
rewrite-plan
    ↓
one contiguous region in one block
    ↓
RealizationIdentity(P, R) from (P, R) only
    ↓
exact match with PlanIdentity
    ↓
construct candidate P'     source P untouched
    ↓
CandidateId(P') = canonical(P')
    ↓
bind external witness to that id and device D
    ↓
HB* projection on a bijective π_R
    ↓
IsLegal oracle
    ↓
commit or discard
```

```text
object canonical text for this pattern = "2"
prose label O2 is not that string
E_sem(P') = Im(π_R)
evict / transfer are machinery events
P' = P means canonical(P') = canonical(P)
match=yes and applied=no is a postcondition failure
match=no and applied=yes is forbidden
```

A yes-plan envelope must carry
`transformation=keep-evict-transfer-restore`. Any other
text is a malformed envelope: no apply.

Generated `op-id` values `E.evict`, `E.transfer`, and
`E.restore` must not already occur in `P`. Every `op-id`
in `P'` is unique. A collision is a postcondition
failure: `match=yes`, `applied=no`, `P` unchanged.

Success still does not grant `can-run-plan`.

## Host

```bash
python3 runtime/record_storage_apply.py --print-apply-contract
python3 runtime/record_storage_apply.py --print-apply-matrix
```

Schema `s2c2.storage_apply.v1`. Source schema
`s2c2.storage_rewrite.v1`. Witness schema
`s2c2.apply_legality_witness.v1`.

## Acceptance scenario

`w0-3-2-storage-capacity-001` is the regression anchor for
this host. It replays the producers already on main
(authorization → 7B envelope → apply) and pins
`canonical(P)`, `canonical(P')`, and `ApplyResult`.

```bash
python3 runtime/record_apply_scenario.py --print-apply-scenario
```

Same source `P`, same envelope, same witness must yield
the same `canonical(P')` and the same `ApplyResult`.
Evidence scope is contract-level and host-level.
`compiler-e2e` stays no. Not `s2c2-opt`. Not hardware
execution. Not a performance claim. Not a new semantic
cut. `can-run-plan` stays no.
