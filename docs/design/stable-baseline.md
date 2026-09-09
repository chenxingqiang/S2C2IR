# Stable Baseline (5A–6B)

**Status:** FROZEN. Phases 5A–5D, 6A, and 6B form the
current production stack. Phase **5E is not opened**.
Phase **6C rewrite is not opened**. 6C design lives above
this freeze: [`storage-capacity.md`](storage-capacity.md).
Do not retune 5A–5D, do not change `#69`, `cost-v04`,
`default-3g`, rewrite license, or the Evidence DB contract.

```text
5A–5D   measured campaign freeze
   ↓
6A      production compiler path
   ↓
6B      Evidence DB / deterministic snapshot
   ↓
──────── STABLE BASELINE ────────
   ↓
6C      Capacity-aware residency   ← design; rewrite not opened
```

```text
Goal     freeze the verified stack as the compiler baseline
Not      a new F, a rewrite, or 6C rewrite implementation
Rewrite  still only from an existing capability license
```

```text
Legality              ≠  Selection  ≠  Cost
Evidence              ≠  rewrite license
selection             ≠  rewrite license
5A–5D freeze          ≠  hunt for diverge=yes
6B Evidence DB        ≠  hardware-ledger
6C                    ≠  another KEEP/TRANSFER rule
```

## What is frozen

| Layer | Object |
| ----- | ------ |
| 5A–5D | every existing enumerated Storage \(F\), both devices, ArgMin = `default-3g`, `diverge=no` |
| 6A | `s2c2-opt --profile` + `--schedule-policy` + `--explain` |
| 6B | `s2c2.evidence.v1` identity \(E=(profile, workload, candidate, revision)\) |

Compiler path:

```text
s2c2-opt
  ↓
profile
  ↓
Evidence DB  →  revision-explicit v1 snapshot
  ↓
F(program)
  ↓
policy selection
  ↓
rewrite license   (independent; still no)
```

```text
#69              unchanged
cost-v04         frozen
default-3g       unchanged
Evidence DB      unchanged
F(program)       unchanged
rewrite license  unchanged
4B chain def     unchanged
```

## 6C rewrite is not this freeze

6C **design** is [`storage-capacity.md`](storage-capacity.md):
\(F_{\mathrm{capacity}}\) and occupancy candidates.
6C-B emits those candidates as `s2c2-opt --capacity`
diagnostics (`rewrite=no`). Rewrite, ranking, and
`measured-capacity-v1` stay closed.

When 6C is implemented, it is a new Storage problem class:

```text
HBM capacity
   ↓
live residency
   ↓
candidate schedules
   ↓
evict / retain / rematerialize
   ↓
policy selection
   ↓
rewrite license
```

It reuses Evidence DB. It does **not** invent a second
campaign store. It does **not** start from a new
KEEP/TRANSFER local action. It answers: when fast memory
is finite, which objects stay where.

Do **not** implement 6C rewrite from this freeze. Do **not**
FileCheck microseconds.

## Out of scope

```text
opening 5E or 6C rewrite
re-measuring 5A–5D
hunting for diverge=yes
changing cost-v04 / default-3g / #69
changing Evidence DB identity or export-revision-required
C||Storage flatten
invented sibling sched.wait
FileCheck of microseconds
```
