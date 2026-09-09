# Measured Storage Cost Policy (Phase 5A)

**Status:** rank a **fully enumerated** \(F(\text{program})\) under
`policy=measured-storage-v1` using **candidate-local** records.
This is a **new policy**. It does **not** add structural ticks to
frozen `cost-v04`, does **not** decide legality, does **not**
replace `default-3g`, and does **not** rank a truncated product.
Frozen `--s2c2-cost` / `--s2c2-argmin` / Score_3 stay untouched.
Not a new Capability grid. Does **not** flatten `C||Storage`,
overwrite `#69`, change the 4B chain definition, FileCheck
microseconds, or apply the measured winner as a rewrite.

4D freeze:
[`storage-cost.md`](storage-cost.md).

```text
complete F(program)                 ← only when enumerated
        ↓
candidate signature = joinGlobal
        ↓
MeasuredCostRecord (profile + signature)
        ↓
ArgMin among measured inhabitants
default-3g selected stays the historical tuple
cost-v04 stays frozen
```

```text
Legality              ≠  Selection  ≠  Cost
cost-v04              ≠  measured-storage-v1
measured-storage-v1   ≠  default-3g
measurement           ≠  semantic truth
measurement           →  ranking evidence
ranking               ≠  rewrite license
ranking               ≠  new Capability measurement
```

## Why this cut

4D proved that structural ticks coincide with `default-3g` on
current enumerated \(F\). Another tick would only retune a
heuristic. This policy asks a different question: given at least
two **already legal** inhabitants and candidate-local times,
does ArgMin differ from the historical tuple?

```text
|F(program)| ≥ 2
    and ≥ 2 inhabitants have
      measured=yes && correctness=1
    → rank those inhabitants
    → diverge=yes  iff ArgMin ≠ default-3g
    → diverge=no   iff ArgMin = default-3g
product > 64
    → ranked=not-enumerated
< 2 usable measured inhabitants
    → ranked=not-measured
measured=no / pending
    → not ranking evidence
```

Unmeasured members are not invented. ArgMin is over the
**measured subset** of enumerated \(F\), not over a guessed
complete table.

## Record

Candidate-local. One row is not a hardware law.

```text
MeasuredCostRecord {
    schema               s2c2.measured_storage_cost.v1
    profile              rtx4090 | 910B | …
    workload_class       human label
    candidate_signature  joinGlobal(S)
    measured_time_us     integer  (table field; do not FileCheck)
    repetitions          integer
    correctness          1 required to rank
    source               fixture-table | device-log | …
    measured             yes | no | pending
}
```

Matching key: `(profile, candidate_signature)` plus
`measured=yes` **and** `correctness=1`. Last usable row wins.
`measured=no` and `pending` are parsed and rejected.
`workload_class` is diagnostic.

```text
measured=yes  && correctness=1  →  ranking evidence
measured=no                     →  not-measured (schema only)
pending                         →  not-measured
correctness≠1                   →  not ranking evidence
```

The checked-in table is a **schema witness**
(`source=fixture-table`, `measured=no`). The compiler must
**not** rank it. A lit-only synthetic table with
`measured=yes` and `source=synthetic-test` proves that usable
evidence can pick a different inhabitant than `default-3g`.
That synthetic table is **not** a live 4090 or 910B campaign
and is **not** a Capability cell.

The 4090 two-tile pipeline log fills the same schema with
`measured=yes` and `source=device-log`. Mapping is local to
this workload: `evi` → S0 PREFETCH, `seq` → S1 PRESERVE.
`par` is not an \(F(\text{program})\) inhabitant. Do not
FileCheck microseconds. Not a Capability cell.

## Witness

`storage-aware-pipeline` on 4090, product=2:

```text
S0 = MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER
     default-3g   cost-v04 ArgMin
S1 = MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PRESERVE|TRANSFER
     alternative legal inhabitant
```

Checked-in fixture (`measured=no`):

```text
measured-storage-v1   ranked=not-measured
```

Synthetic test table (`measured=yes`, not a device log):

```text
cost-v04              ranked=S0  diverge=no
measured-storage-v1   ranked=S1  diverge=yes
```

4090 device-log (`source=device-log`, `measured=yes`):

```text
S0 evi  <  S1 seq
measured-storage-v1   ranked=S0  diverge=no
cost-v04              ranked=S0  diverge=no
```

On this device and this \(F\), measured ArgMin **coincides**
with `default-3g`. That is a 4090 fact for this pair, not a
claim that the two policies are the same object, and not a
rewrite of S0.

```text
diverge=no on 4090
    ≠  cost-v04 ≡ measured-storage-v1
    =  this device table picks the historical tuple
rewrite of the winner
    =  not this cut
```

Truncated `@seven_binary_chains` (product=128):
`ranked=not-enumerated`. Hierarchy without matching rows:
`ranked=not-measured`.

## Policy

```text
policy = measured-storage-v1
ranked ∈ {S ∈ F | measured=yes ∧ correctness=1}
         when that set has size ≥ 2
default-3g selected = historical tuple (unchanged)
cost-v04 = FROZEN
Capability grid = unchanged
rewrite of the measured winner = not this cut
```

## Out of scope

```text
adding structural ticks to cost-v04
wrapping table times as wall-clock FileCheck
FileCheck of 4090 microseconds
910B per-candidate campaign (later)
applying the measured winner as a rewrite
applying the measured winner as a rewrite
new 4090 / 910B Capability measurements
changing --s2c2-cost / --s2c2-argmin / --s2c2-walk
retargeting default-3g
changing the 4B chain definition
overwriting #69
C||Storage flatten
invented sibling sched.wait
memory-capacity-aware residency (later)
```
