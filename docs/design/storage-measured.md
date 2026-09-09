# Measured Storage Cost Policy (Phase 5A)

**Status:** **FROZEN** (`#95` / `#96`). Measured-cost plumbing is
open. Rank a **fully enumerated** \(F(\text{program})\) under
`policy=measured-storage-v1` using **candidate-local** records.
On the two-tile pipeline, both 4090 and 910B pick S0 with
`diverge=no`. That is **not** a policy identity. 5B, 5C, and
5D later measured every remaining enumerated \(|F|>2\) and
also froze as `diverge=no`. The campaign is closed
([`storage-measured-campaign.md`](storage-measured-campaign.md)).
Do **not** hunt for divergence by retuning a pair. This policy does **not** add
structural ticks to frozen `cost-v04`, does **not** decide
legality, does **not** replace `default-3g`, and does **not**
rank a truncated product. Frozen `--s2c2-cost` / `--s2c2-argmin`
/ Score_3 stay untouched. Not a new Capability grid. Does
**not** flatten `C||Storage`, overwrite `#69`, change the 4B
chain definition, FileCheck microseconds, or apply the measured
winner as a rewrite.

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

The 4090 and 910B two-tile pipeline logs fill the same schema
with `measured=yes` and `source=device-log`. Mapping is local
to this workload: `evi` → S0 PREFETCH, `seq` → S1 PRESERVE.
`par` is not an \(F(\text{program})\) inhabitant. Do not
FileCheck microseconds. Do not compare 4090 μs to 910B μs.
A 4090 row is not 910B ranking evidence. Not a Capability cell.

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

910B device-log (`source=device-log`, `measured=yes`):

```text
S0 evi  <  S1 seq
measured-storage-v1   ranked=S0  diverge=no
cost-v04              ranked=S0  diverge=no
```

On each device and this \(F\), measured ArgMin **coincides**
with `default-3g`. That is a per-device fact for this pair,
not a claim that the two policies are the same object, not
a claim that 4090 ≡ 910B, and not a rewrite of S0.

```text
diverge=no on 4090
diverge=no on 910B
    ≠  cost-v04 ≡ measured-storage-v1
    ≠  4090 μs comparable to 910B μs
    =  each device table picks the historical tuple
rewrite of the winner
    =  not this cut
```

## Freeze

```text
4090  ArgMin S0 = default-3g S0 → diverge=no
910B  ArgMin S0 = default-3g S0 → diverge=no
#69              unchanged
cost-v04         frozen
default-3g       unchanged
rewrite license  unchanged
```

Plumbing is proven. Policy divergence is **not**. Do not
re-measure this S0/S1 pair to manufacture `diverge=yes`.
Phase 5B is **FROZEN**
([`storage-measured-5b.md`](storage-measured-5b.md)):
hierarchy 8/8 measured, both devices `diverge=no`. Do not
re-measure that 8-set. Phase 5C design:
[`storage-measured-5c.md`](storage-measured-5c.md).

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
FileCheck of 4090 / 910B microseconds
comparing 4090 μs to 910B μs
applying the measured winner as a rewrite
re-measuring pipeline S0/S1 to manufacture diverge=yes
re-measuring the frozen hierarchy 8-set
new 4090 / 910B Capability measurements
Phase 5C implementation before that design is approved
changing --s2c2-cost / --s2c2-argmin / --s2c2-walk
retargeting default-3g
changing the 4B chain definition
overwriting #69
C||Storage flatten
invented sibling sched.wait
memory-capacity-aware residency (later)
```
