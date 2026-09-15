# Evidence Algebra / Decision Model (Stage A)

**Status:** design freeze from `0f96895` (6C-J/K/L merged).
Not a rewrite. Not a new \(F\). Not `sufficient=yes`.
Not a 6B Evidence DB identity change. Not an expansion of
`S2C2CapabilitySchedule.cpp`.

```text
Goal     freeze Evidence → Predicate → Decision as first-class records
Not      a giant sufficient AND, restore-target classifier, license, or rewrite
Rewrite  still only from an existing capability license
```

6C-J / 6C-K / 6C-L stay FROZEN occupancy *kinds*. This cut
does **not** add another boolean conjunct. It names the
record those kinds already inhabit.

## Architectural constitution

These six invariants are not optional. Later PRs, including
parked 6C-M, must not collapse them.

```text
1. HB_source is semantic truth
2. Realization does not change HB
     membership uses HB_M = HB_source
     backend extra order is not written back into S²C² IR
3. Unknown → safe no / Preserve
4. Evidence ≠ authorization
5. Query ≠ rewrite
6. source-data
     ≠ restore-ordering
     ≠ dest-invalidation
     ≠ sufficient
     ≠ rewrite-license
```

Derived occupancy fact, already frozen by 6C-K:

```text
usable = source-data ∧ restore-ordering
usable ≠ dest-invalidation
```

## Why not 6C-M sufficient next

A lone

```text
sufficient = usable ∧ dest-invalidation ∧ …
```

is mathematically legal and architecturally the wrong next
cut. It grows a procedural AND chain inside the capacity
query printer, then hides *why* the answer is no.

The dest-invalidation fixture already proves the needed
non-implication:

```text
usable=yes
dest-invalidation=yes
sufficient=no
rewrite-license=no
rewrite-path=no
```

That row stays the lock. 6C-M (`sufficient` as a query
boolean) is **parked**. It is not authorized by this freeze.

## Layers (do not collapse)

```text
Evidence
   ↓
Predicate
   ↓
Decision
   ↓
License          CLOSED
   ↓
Rewrite          CLOSED
```

```text
                    ┌─────────────────────┐
                    │   S²C² Semantic IR  │
                    └──────────┬──────────┘
                               ▼
                    ┌─────────────────────┐
                    │ Execution Semantics │
                    └──────────┬──────────┘
                               ▼
                    ┌─────────────────────┐
                    │   Realization Space │
                    └──────────┬──────────┘
                               ▼
                    ┌─────────────────────┐
                    │      Evidence       │
                    │  kinds, not AND     │
                    └──────────┬──────────┘
                               ▼
                    ┌─────────────────────┐
                    │      Decision       │
                    │ subject + result    │
                    │ + reasons           │
                    └──────────┬──────────┘
                               ▼
                    ┌─────────────────────┐
                    │   Authorization     │  CLOSED
                    └──────────┬──────────┘
                               ▼
                    ┌─────────────────────┐
                    │      Rewrite        │  CLOSED
                    └─────────────────────┘
```

6B Evidence DB identity

```text
E = (profile, workload, candidate, measurement_revision)
```

is a **measured ranking store**. Occupancy kinds are a
**query proof store**. They share the word “evidence” and
must not share a schema.

```text
s2c2.evidence.v1              ≠  s2c2.evidence_kind.v1
measured cost record          ≠  occupancy witness
```

## Evidence record

Schema `s2c2.evidence_kind.v1` (defined, not ingested this
cut):

```text
kind            token; see kind table
object          occupancy id (tileN normalizes to N); n/a if unused
witness         token; unknown → no
scope           token; unknown → no
applicability   yes | no | n/a
reason          typed token; never empty on no
```

Unknown witness or unknown scope ⇒ `applicability=no`.
Unknown does not invent a validity FSM.

### Frozen occupancy kinds (6C-J/K/L)

| kind | Witness | Scope | Proves |
| ---- | ------- | ----- | ------ |
| `source-data` | `spec-unmutated-cover` | `occupancy-live` | scoped replica covers occupancy live |
| `restore-ordering` | `spec-before-consumer` | `occupancy-live` | TRANSFER at `occ.end` |
| `dest-invalidation` | `spec-drop-stale` | `occupancy-live` | fast-space copy dropped without stale reads |

`usable` is **not** a kind. It is a predicate over two
kinds.

### Named, not classified this cut

| kind | Intent | Not |
| ---- | ------ | --- |
| `restore-target` | restore may re-occupy occupancy destination | dest-invalidation, rewrite-path |
| `live-bytes` | `LiveBytes(t)` feasibility | tile-count occupancy |
| `alias` | distinct objects / overlapping storage | IR discovery |
| `lifetime` | producer–consumer interval proof | valid/stale/dirty FSM |

These names reserve the algebra. They do **not** open
parsers, classifiers, or `F_storage_schedule`.

## Predicate vs Decision

A **predicate** is a named view over kinds:

```text
usable(selected) = source-data ∧ restore-ordering
```

A **decision** is the compiler-facing record for **one
named predicate**. `result` without `subject` is not a
Decision: callers cannot tell which question was answered.

```text
Decision
  subject    named predicate being decided
  result     yes | no | n/a
  reasons[]  typed tokens from kinds / predicates
```

```text
Decision
  subject=usable
  result=yes
  reasons=source-data-present, restore-ordering-present
```

is the required shape this cut. Not a subject-less
`result=no`, and not:

```text
sufficient = A ∧ B ∧ C ∧ D ∧ …  → false
Decision.subject=sufficient  result=no
```

This cut does **not** print a new per-EVICT decision
object from `s2c2-opt`. Existing 6C-J/K/L prefixes remain
the occupancy printers. The host contract below freezes
the algebra.

Forced:

```text
Decision.subject          required
Decision.subject=usable   ≠  Decision.subject=sufficient
this cut emits            Decision.subject=usable only
this cut does not emit    Decision.subject=sufficient
Decision.result=yes       ≠  rewrite-license=yes
Decision.result=yes       ≠  rewrite-path=yes
query                     ≠  rewrite
```

On the dest-invalidation fixture the implied records are:

```text
kinds  (independent evidence; not Decision conjuncts)
  source-data=yes
  restore-ordering=yes
  dest-invalidation=yes

predicates
  usable=yes

Decision
  subject=usable
  result=yes
  reasons=source-data-present, restore-ordering-present

not emitted this cut
  Decision.subject=sufficient
  Decision.result=no + reasons=sufficient-not-composed
  sufficiency-evaluation=n/a   (6C-M parked; not a Decision)

rewrite-license=no
rewrite-path=no
```

`dest-invalidation=yes` stays an evidence record. It does
not become a sufficiency Decision. Parked 6C-M must not be
smuggled in as `result=no` on an unnamed subject.

### Reason tokens (examples this cut)

`reasons[]` are typed tokens, not free-form strings. This
cut froze the Decision *shape* and a few examples. Closed
namespaces (`evidence.*` / `predicate.*` / `decision.*` /
`authorization.*`) are the next freeze:
[`evidence-reason-vocab.md`](evidence-reason-vocab.md).

## God object

Do **not** fold this algebra into
`S2C2CapabilitySchedule.cpp`.

```text
Evidence / Decision   later: dedicated analysis module
Capability schedule   frozen pair-license / occupancy query host
6B Evidence DB        frozen measured identity E
```

A later implementation cut may add a small printer. It
must not become `CapabilityDecision.cpp`.

## Roadmap (not this PR)

```text
Stage A   Evidence algebra / Decision records     ← this freeze
Stage B   physical capacity (LiveBytes, alias, lifetime, allocator)
Stage C   composed sufficiency → license → rewrite
```

Stage B is still query/proof. Stage C still requires an
explicit `PR #N — APPROVED` and still distinguishes
evidence from authorization.

## Out of scope

```text
sufficient=yes print
Decision.subject=sufficient
Decision.result=no + reasons=sufficient-not-composed
restore-target / live-bytes / alias / lifetime classifiers
rewrite-license=yes
rewrite-path / replace / erase
F_storage_schedule
expanding S2C2CapabilitySchedule.cpp
changing 6C-J / 6C-K / 6C-L classification
changing 6B Evidence DB identity
changing architecture-healthcheck.md scores
new Capability matrix
frontend / extra vendors
FileCheck of microseconds
closed reason-token vocabulary → evidence-reason-vocab.md
```

## Host contract

```bash
python3 runtime/record_decision.py --print-evidence-decision-contract
```

Query-only. `Decision.subject=usable`.
`sufficiency-evaluation=n/a`. `rewrite-license=no`.
`rewrite-path=no`. Diagnostic `--capacity` does not print
this prefix.
