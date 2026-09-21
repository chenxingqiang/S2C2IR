# Realization Legality v1

**Status:** design freeze from `3b30d5c` (PR #128 merged).
Not a rewrite. Not `sufficient=yes`. Not 6C-M.
Not can-run-plan. Not authorization.
Not an expansion of `S2C2CapabilitySchedule.cpp`.
Does not add capability kinds. Does not change applicable
semantics.

```text
Goal     normalize Capability Profile constraint facts into
         per-kind legality facts
Not      sufficient, can-run-plan, authorization, or rewrite
Rewrite  still only from an existing capability license
```

#128 aggregates applicability into a profile. This cut
answers a different question:

```text
For an already-frozen Capability Profile, does a
realization violate those constraint facts?
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
Realization Legality             ← this freeze
   ↓
Sufficiency                      CLOSED
```

## Architectural constitution

```text
legality   ≠ applicable
legality   ≠ profile
legality   ≠ sufficient
allowed    ≠ can-run-plan
unproven   ≠ forbidden
legality   ≠ authorization
legality   ≠ rewrite-license
```

Constraint tokens are **copied**, not remapped:

```text
allowed | forbidden | not-applicable | unproven
```

Do not invent a parallel result enum.

## Schema `s2c2.realization_legality.v1`

Input: `s2c2.capability_profile.v1` only. Do not re-read
occupancy EvidenceRecords. Do not re-run
`derive_applicable_decision`.

Envelope (one profile):

```text
schema              s2c2.realization_legality.v1
source-schema       s2c2.capability_profile.v1
identity            (target, device)
facts[]             one legality fact per closed kind
sufficiency-evaluation  n/a
can-run-plan            no
rewrite-license         no
rewrite-path            no
```

Each fact:

```text
schema      s2c2.realization_legality.v1
identity    (target, device, kind)
constraint  copied from profile.capabilities[kind]
reasons[]   copied from that entry
```

Identity of a fact is `(target, device, kind)`, not a plan
id.

## Forbidden implications

```text
all capabilities = allowed   ≠  sufficient
all capabilities = allowed   ≠  can-run-plan=yes
legality=allowed             ≠  rewrite-license=yes
legality=forbidden           ≠  rewrite-path=no
legality=unproven            ≠  forbidden
legality                     ≠  authorization
```

This layer is FACT, not DECISION TO EXECUTE.

## Negative fixture matrix

| Case | Profile | Legality |
| ---- | ------- | -------- |
| allowed-from-yes | pair applicable=yes | pair `allowed` |
| forbidden-from-no | pair applicable=no | pair `forbidden` |
| not-applicable-from-na | dma n/a | dma `not-applicable` |
| unproven-from-missing | empty profile | all `unproven`; not `forbidden` |
| unproven-from-unknown-provenance | pair provenance=unknown | pair `unproven` |
| all-allowed-ne-sufficient | all three allowed | three `allowed`; still `sufficiency-evaluation=n/a` `can-run-plan=no` |
| one-kind-forbidden | pair forbidden, others allowed | not collapsed |
| mixed-allowed-unproven | pair allowed, others missing | mixed facts |

## God object

```text
this host module           Realization Legality
Capability Profile         frozen aggregation
Capability applicability   frozen per-kind Decision
Capability schedule        frozen pair-license host; do not expand
```

## Out of scope

```text
sufficient=yes
Decision.subject=sufficient
can-run-plan=yes
plan feasibility
schedule search / placement
authorization.*
rewrite-license=yes
rewrite-path / replace / erase
F_storage_schedule
6C-M
generic schema validator
new capability kinds
new targets
changing applicable semantics
expanding S2C2CapabilitySchedule.cpp
FileCheck of microseconds
```

## Host contract

```bash
python3 runtime/record_realization_legality.py --print-realization-legality-contract
python3 runtime/record_realization_legality.py --print-realization-legality-matrix
```

Query-only. `can-run-plan=no`. `rewrite-license=no`.

Realization Checking (claimed-kinds vs frozen legality facts;
not can-run-plan):
[`realization-checking.md`](realization-checking.md).
Baseline E2E Integration (compose frozen hosts; no new
semantics):
[`realization-checking-e2e.md`](realization-checking-e2e.md).
