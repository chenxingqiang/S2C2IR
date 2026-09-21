# Realization Checking v0

**Status:** implementation of the frozen Checking contract
from `aa51e8e` (PR #129 merged).
Not a rewrite. Not `sufficient=yes`. Not 6C-M.
Not can-run-plan. Not authorization.
Not an expansion of `S2C2CapabilitySchedule.cpp`.
Does not modify Profile or Legality. Does not add kinds.

```text
Goal     Check(r, L) → per-kind findings, or contract-error
Not      sufficient, can-run-plan, authorization, or rewrite
Rewrite  still only from an existing capability license
```

#129 copies profile constraints into legality facts. This cut
answers a different question:

```text
Does candidate realization r satisfy the already-frozen
legality facts L, for the kinds r actually claims?
```

It does **not** answer “can this plan run?”.

```text
EvidenceRecord
   ↓
Predicate
   ↓
Decision.usable / applicable     FROZEN
   ↓
Independent Report               FROZEN
   ↓
Capability Profile               FROZEN (#128)
   ↓
Realization Legality             FROZEN (#129 / aa51e8e)
   ↓
Realization Checking             ← this cut
   ↓
Sufficiency                      CLOSED
```

## Architectural constitution

```text
Check only claimed-kinds.
unclaimed frozen kinds in L      ≠  violation
satisfy                          ≠  can-run-plan=yes
violate                          ≠  rewrite-path
unproven                         ≠  forbidden
unproven                         ≠  missing
all satisfy                      ≠  sufficient
contract-error                   ≠  legality result
```

Finding keeps the source fact:

```text
{ kind, result, constraint }
```

```text
allowed         → satisfy  + constraint=allowed
forbidden       → violate  + constraint=forbidden
not-applicable  → violate  + constraint=not-applicable
unproven        → unproven + constraint=unproven
```

No aggregate `all-satisfy`.

## Schema

`L` = `s2c2.realization_legality.v1` (complete closed bag).
`r` = `s2c2.realization_claim.v1`.

```text
r.identity        (target, device)   # must equal L.identity
r.claimed-kinds   required; unique subset of frozen KINDS,
                  canonical order
```

`claimed-kinds=[]` is a legal empty claim (`status=ok`,
`findings=[]`). **Absent** `claimed-kinds` is
`contract-error invalid-schema`, not an empty claim.

```text
["staged-dma", "concurrent-pair", "staged-dma"]
        ↓
["concurrent-pair", "staged-dma"]
```

`L.facts[]` is a complete closed bag **in frozen KINDS
order**. Each fact:

```text
schema      s2c2.realization_legality.v1
identity    (target, device, kind)   # all three required
constraint  allowed | forbidden | not-applicable | unproven
```

Top-level `kind` on a fact is not a fallback and is
`malformed-legality`. Wrong per-fact `schema` is
`malformed-legality`. Missing frozen kind in `L` is
`malformed-legality`, not `unproven`.

Envelope `s2c2.realization_checking.v1`:

```text
status                  ok | contract-error
findings[]              0..3 rows, KINDS order among claimed kinds
sufficiency-evaluation  n/a
can-run-plan            no
rewrite-license         no
rewrite-path            no
```

Contract errors (`findings=[]`):

```text
identity-mismatch | unknown-kind | malformed-legality | invalid-schema
```

`L` missing a frozen kind is `malformed-legality`, not `unproven`.
Absent `r.claimed-kinds` is `invalid-schema`, not empty claim.

## Negative fixture matrix

17 cases locked in derive. The original 13 plus input
integrity:

```text
missing-claimed-kinds
malformed-L-bad-fact-schema
malformed-L-missing-identity-kind
malformed-L-conflicting-kind
```

## Out of scope

```text
sufficient=yes
Decision.subject=sufficient
can-run-plan=yes
all-satisfy / overall
plan feasibility
authorization.*
rewrite-license=yes
rewrite-path
F_storage_schedule
6C-M
generic schema validator
new capability kinds
changing applicable / Profile / Legality
expanding S2C2CapabilitySchedule.cpp
FileCheck of microseconds
```

## Host contract

```bash
python3 runtime/record_realization_checking.py --print-realization-checking-contract
python3 runtime/record_realization_checking.py --print-realization-checking-matrix
```

Query-only. `can-run-plan=no`. `rewrite-license=no`.

Baseline E2E Integration (compose frozen hosts; no new
semantics):
[`realization-checking-e2e.md`](realization-checking-e2e.md).
Cross-identity Checking E2E (compose frozen cuda / ascend /
cpu identities; no new semantics):
[`realization-checking-xid.md`](realization-checking-xid.md).
