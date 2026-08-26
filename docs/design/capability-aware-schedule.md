# Capability-Aware Schedule (Phase 3A)

**Status:** MVP. Not Cost v0.4. Does **not** change S²C² semantics,
HB axioms, `R`, Search, Transformation, Pilot A/B/C bodies, or any
`--cuda-val*` timed body.

```text
Same S²C² program
+ different CUDA capability profiles
→ automatically choose different legal schedules
```

Capability Matrix is **compiler decision input**, not a dataset archive.

---

## 1. Pipeline

```text
CapabilityRecord schema     docs/design/v3-capability-schema.md
        ↓
Applicability               measured ∧ sync ∧ size_range
        ↓
Capability Query            --s2c2-capability-query
        ↓
CapabilityFilter            --s2c2-capability-schedule
        ↓
check-s2c2-execution        HB_before ⊆ HB_after
```

This pass asks only:

```text
Which schedules are capability-compatible / worthwhile candidates?
```

It does **not** ask which schedule is faster. Cost v0.4 is Phase 3C.

---

## 2. Query

```text
s2c2-opt --s2c2-capability-query="device=rtx4090 producer=comp.silu consumer=comm.htod"
```

```json
{
  "pair": "C||HtoD",
  "pair_relation": "parallel",
  "observed_constraint": "none",
  "confidence": "measured",
  "applicable": "unknown"
}
```

Catalog query has no payload size, so a ranged cell is `unknown`.

```text
producer=comp.silu consumer=comp.gemm
```

4090:

```json
{
  "pair": "C_silu||C_gemm",
  "pair_relation": "serial",
  "observed_constraint": "resource_contention",
  "confidence": "arm_specific",
  "applicable": false
}
```

Recorder catalog query:

```text
runtime/cuda/record_v3.py --query-cap C||HtoD
```

MVP pairs:

```text
C||HtoD
C||DtoH
HtoD||DtoH
C||C
C_silu||C_gemm
```

Host-like spaces (`host`, `ssd`) → device-like (`hbm`, `dram`, `sram`)
are classified as HtoD. The reverse is DtoH.

---

## 3. Schedule rewrite

There is no `sched.serial` op. Serializing a concurrent group unbundles
`sched.task`s into the **parent block in IR order**. Parent program
order is one legal total order of `NoOrderingRequirement`.

```text
pair_relation = parallel | mixed | underdetermined  → keep
pair_relation = serial AND applicable = yes
                 AND rewrite_license ≠ no           → flatten
otherwise                                           → keep
```

Applicability (Phase 3A conservative):

```text
confidence = measured
AND synchronization matches (default named-nonblocking)
AND size_range is n/a or the static payload is inside the range
```

A pair may have **several** `size_range` records. Lookup picks the
narrowest covering band. Catalog query with no payload size and
more than one ranged cell, or more than one unconstrained `n/a`
cell, returns `underdetermined` / `size_range=multiple`. See
[`capability-size-applicability.md`](capability-size-applicability.md).

Not used for destructive rewrite:

```text
confidence = arm_specific | inferred | unknown
size_range present but payload unknown or outside the range
rewrite_license=no in note (size-banded evidence, not yet licensed)
```

4090:

```text
C || HtoD     parallel   keep (and tiny IR is outside 16MiB..256MiB)
SiLU || GEMM  serial     keep: arm_specific evidence, not a global rule
C || C        serial     flatten measured occupancy cell (size_range n/a)
```

Synthetic `npu-demo` (not measured, `inferred`):

```text
all pairs     keep       inferred is not production evidence
```

Same IR, different profile, different schedule on the **applicable**
measured cell (`C||C`), not by promoting `arm_specific` to ∀ programs.

---

## 4. Semantic invariant

```text
Capability optimization preserves semantic validity
Concurrent → serial realization   allowed
Pipeline StageOrder               must not be broken
HB_before ⊆ HB_after
Do not invent sibling sched.wait
```

`--check-s2c2-execution` runs after every rewrite in the tests.
Flattening concurrent siblings may add parent PO edges. That is a
more conservative realization, not a new semantic dependency.

---

## 5. Out of this MVP

```text
Cost v0.4 ranking
D2D / P2P as the next CUDA arm
second real hardware (prefer ROCm after this lands)
breaking StageOrder
changing Concurrent = NoOrderingRequirement
letting arm_specific evidence rewrite IR
using npu-demo inferred cells as production evidence
```
