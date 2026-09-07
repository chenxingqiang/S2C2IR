# Evidence-Bounded Schedule (Phase 3D)

**Status:** compiler optimizer entry. Not Cost v0.4. Does **not**
densify Capability matrices, overwrite `#69`, invent
`910B C||C = parallel`, or rank candidate schedules.

Project narrative:
[`evidence-bounded-optimizer.md`](evidence-bounded-optimizer.md).
Profile schema:
[`compiler-profiles/README.md`](compiler-profiles/README.md).

```text
s2c2-opt is the product
measurement is an input
Cost v0.4 stays closed
```

## Why this increment

Phase 3A–3C proved the mechanism:

```text
IR → Capability → Applicability → Rewrite License → flatten → HB
```

That lived behind `--s2c2-capability-schedule` plus explicit JSONL
paths. Phase 3D makes it a compiler driver:

```bash
s2c2-opt input.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule
s2c2-opt input.mlir --s2c2-evidence-bounded-schedule=profile=910B
s2c2-opt input.mlir --profile=unknown --s2c2-evidence-bounded-schedule
```

`--s2c2-capability-schedule=profile=<jsonl>` is unchanged.

## Pipeline

```text
original IR
   ↓
load compiler profile
   ↓
query capability (EvidenceQuery)
   ↓
check applicability
   ↓
check rewrite_license
   ↓
generic concurrent → serial rewrite
   ↓
verify HB (--check-s2c2-execution)
```

Generic rewrite infrastructure (one inhabitant this increment):

```text
RewriteCandidate     2-task sched.concurrent / sched.overlap
    ↓
EvidenceQuery        pair + size → CapCell
    ↓
Applicability        measured ∧ sync ∧ size_range
    ↓
RewriteLicense       rewrite_license != no
    ↓
Rewrite              unbundle into parent IR order
    ↓
Verifier             check-s2c2-execution
```

Pair kind is **not** in the rewrite. `C||C` and `HtoD||HtoD` share
the same flatten. Do not add C||HtoD / pipeline rewrites here.

## Acceptance

Same MLIR (`test/Integration/evidence-bounded-schedule.mlir`):

| Profile | 16MiB C\|\|C | 128MiB C\|\|C | prefetch \|\| MLP | HtoD\|\|HtoD |
| ------- | ------------ | ------------- | ----------------- | ------------ |
| `rtx4090` | serialize | serialize | keep | serialize |
| `910B` | keep (mixed, unlicensed) | serialize | keep | keep (no cell) |
| `unknown` | keep | keep | keep | keep |

`--check-s2c2-execution` after every rewrite. `check-s2c2` must pass.

`--evidence=` pointing at `#69` `capability.jsonl` with
`profile=910B` keeps both `C||C` bands.

## CLI

```text
s2c2-opt input.mlir \
  --profile=rtx4090 \
  --evidence=docs/design/v3-dataset/...jsonl \
  --s2c2-evidence-bounded-schedule \
  --check-s2c2-execution
```

Pass options override the top-level flags (space-separated, same
as `--s2c2-capability-schedule`):

```text
--s2c2-evidence-bounded-schedule="profile=910B evidence=/path/to.jsonl"
--s2c2-evidence-bounded-schedule=profile=docs/design/compiler-profiles/910B.json
```

Default profile is `unknown` (preserve). No evidence ⇒ no
destructive optimization.

## Frozen invariants

```text
1. Semantic dependency      ≠  performance serialization
2. Capability classification ≠  rewrite authorization
3. Scoped evidence          ≠  global rule
4. Unknown / underdetermined  ⇒  preserve
5. Rewrite preserves HB / semantic validity
```

## Out of scope

```text
Cost v0.4 ranking
new 4090 / 910B Capability grid points
C||HtoD / HtoD||DtoH / pipeline rewrite kinds
streaming SSD→Host→HtoD→Compute workload (later)
overwriting #69
reading benchmark logs as compiler input
```
