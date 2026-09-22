# W0-3/2 Apply Inhabitant v0

**Status:** host for the frozen IR Apply Contract v0.1
(`038f4a1`, merged @ `2821de8`). One pattern. Not a
generic rewrite engine. Not `Enum_F`. Not Search. Not
authorization. `can-run-plan` stays no.

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

Success still does not grant `can-run-plan`.

## Host

```bash
python3 runtime/record_storage_apply.py --print-apply-contract
python3 runtime/record_storage_apply.py --print-apply-matrix
```

Schema `s2c2.storage_apply.v1`. Source schema
`s2c2.storage_rewrite.v1`. Witness schema
`s2c2.apply_legality_witness.v1`.
