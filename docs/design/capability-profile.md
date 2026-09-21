# Capability Profile / Applicability aggregation

**Status:** design freeze from `d91b93d` (PR #127 merged).
Not a rewrite. Not `sufficient=yes`. Not 6C-M.
Not a generic schema validator.
Not an expansion of `S2C2CapabilitySchedule.cpp`.
Does not add capability kinds.

```text
Goal     aggregate closed capability facts for (target, device)
Not      profile = sufficient, can-run-plan, or a rewrite license
Rewrite  still only from an existing capability license
```

#125/#126 answer *applicable* for one `(target, device, kind)`.
#127 reports usable and applicable independently. This cut
answers a different question:

```text
For one (target, device), which closed capability facts
are proven, which are not, and how they map to realization
constraints?
```

It does **not** answer “therefore sufficient?”.

```text
EvidenceRecord
   ↓
Predicate
   ↓
Decision.subject=usable              FROZEN (#124)
   ↓
Decision.subject=applicable          FROZEN (#125/#126)
   ↓
Independent Report                   FROZEN (#127)
   ↓
Capability Profile                   ← this freeze
   ↓
Realization constraints              facts, not a plan
   ↓
Sufficiency                          CLOSED
```

## Architectural constitution

```text
profile     ≠ applicable
profile     ≠ usable
profile     ≠ sufficient
constraint  ≠ rewrite-license
allowed     ≠ can-run-plan
```

```text
CapabilityProfile.identity = (target, device)
kinds                      = concurrent-pair | named-nonblocking | staged-dma
```

Do **not** add kinds. A growing kind set becomes a second
implicit scheduler.

## Schema `s2c2.capability_profile.v1`

All fields required. Query-only. Not ingested by `s2c2-opt`.

```text
schema
identity        (target, device)
target
device
capabilities[]  one entry per closed kind, in kind order
sufficiency-evaluation  n/a
rewrite-license         no
rewrite-path            no
```

Each `capabilities[]` entry:

```text
kind
decision     s2c2.decision.v1 subject=applicable
reasons[]    copied from that Decision
provenance   catalog | occupancy-query | unknown | missing
constraint   allowed | forbidden | not-applicable | unproven
```

Derivation **calls** frozen `derive_applicable_decision`
once per closed kind. Records are partitioned by
`(target, device, identity.kind)` so one kind cannot
collapse another.

## Evidence vs absence

Decision.result stays `yes | no | n/a`. Profile does **not**
add `result=unknown`. Absence is typed:

```text
yes            positive evidence          → constraint=allowed
no + not-applicable
               explicit negative evidence → constraint=forbidden
n/a            domain does not apply      → constraint=not-applicable
missing-evidence / unknown provenance / duplicate / mismatch
               not enough evidence        → constraint=unproven
```

```text
absence of record  ≠  no
unproven           ≠  forbidden
```

`provenance=missing` means no in-scope record for that
kind. `provenance=unknown` means a record was present but
not evidence-backed (#125).

## Realization constraints (not a plan)

```text
CapabilityProfile(target, device)
    ↓
CapabilityConstraint(kind, constraint)
```

```text
concurrent-pair = allowed
staged-dma      = allowed
named-nonblocking = unproven
```

is **not**:

```text
can-run-plan = yes
```

`allowed` is not authorization and not a rewrite license.

## Negative fixture matrix

| Case | Records | Profile |
| ---- | ------- | ------- |
| profile-aggregation | pair yes, named-nonblocking no, dma yes | three independent facts |
| unknown-capability | empty bag | all `missing-evidence` / `unproven`; not `forbidden` |
| one-kind-no | pair no, others yes | pair `forbidden`; others still `allowed` |
| ignore-other-device | other device all yes | this device still `unproven` |
| duplicate-identity | two pair records + named-nonblocking yes | pair `duplicate-identity` `unproven`; named-nonblocking still `allowed` |
| unknown-provenance | pair provenance=unknown | pair `missing-evidence` `unproven`; others unchanged |
| usable-ne-capability | empty cap bag | occupancy usable cannot fill any capability |
| all-yes-ne-sufficient | all three yes | all `allowed`; `sufficiency-evaluation=n/a` |
| no-authorization | mixed; dma n/a | no `authorization.*`; dma `not-applicable` |
| no-rewrite-path | all three yes | `rewrite-path=no` |

```text
concurrent-pair=yes
∧ named-nonblocking=yes
∧ staged-dma=yes
        ↓
CapabilityProfile complete
        ↓
NOT sufficient
```

## God object

```text
this host module           Capability Profile
Capability applicability   frozen per-kind Decision
Occupancy / capability report frozen independent report
Capability schedule        frozen pair-license host; do not expand
6B Evidence DB             frozen measured identity E
```

## Out of scope

```text
sufficient=yes print
Decision.subject=sufficient
can-run-plan=yes
new capability kinds
authorization.* tokens
generic schema validator
rewrite-license=yes
rewrite-path / replace / erase
F_storage_schedule
expanding S2C2CapabilitySchedule.cpp
changing 6C-J/K/L printers
changing v3 catalog JSONL
changing 6B Evidence DB identity
changing architecture-healthcheck.md scores
FileCheck of microseconds
```

## Host contract

```bash
python3 runtime/record_capability_profile.py --print-capability-profile-contract
python3 runtime/record_capability_profile.py --print-capability-profile-matrix
```

Query-only. `rewrite-license=no`. Diagnostic occupancy
`--capacity` does not print these prefixes.

Realization Legality (constraint facts copied; not
sufficient / can-run-plan):
[`realization-legality.md`](realization-legality.md).
Realization Checking (claimed-kinds vs frozen legality facts;
not can-run-plan):
[`realization-checking.md`](realization-checking.md).
