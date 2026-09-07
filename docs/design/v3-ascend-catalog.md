# S²C² Ascend 910B measured catalog (Phase 3B / PR-R2)

**Status:** measured CapabilityRecord cells. Not a compiler backend.
Not Cost v0.4. Does **not** change HB, `R`, Search, Transformation,
`--s2c2-capability-schedule`, or Schema v1 keys.

```text
Same semantic workload
+ Same Capability Schema v1
+ AscendCL realization
→ Measured CapabilityRecord
```

```text
Catalog            ≠  scheduler rewrite
pair_relation      ≠  4090 vs 910B microseconds
confidence=measured ≠  V3 claimed
R4 pinned/pageable ≠  this increment
PR-R3 schedule     ≠  this increment
```

## Grid

```text
N ∈ {4M, 16M, 64M} floats     # 16MiB .. 256MiB
k = 32
warmup = 2
reps = 5 (median)
host memory = aclrtMallocHost (pinned)
streams = named
T_pair = completion(s0, s1)
```

Classifier slack is unchanged (measurement, not a Cost axiom).

If all sizes agree, one JSONL cell per pair with
`size_range=16MiB..256MiB`. If they disagree, the cell is
`underdetermined`. Do not invent a verdict.

Measured projection (this increment):

| Pair | pair_relation | observed_constraint | confidence |
| ---- | ------------- | ------------------- | ---------- |
| `C\|\|HtoD` | underdetermined | none | measured |
| `C\|\|C` | underdetermined | none | measured |
| `HtoD\|\|DtoH` | mixed | none | measured |

`C||C` is **not** a single parallel cell. 4M is mixed; 16M and
64M are serial. The catalog does not majority-vote. PR-R3 is not
licensed by this table.

## Direction convention

`HtoD||DtoH` records keep `direction=host_to_device` and
`source_memory_class=pinned_host` because that is how Schema v1
pair records are written on 4090. Bidirectional pairs do not get
a 910B-specific direction encoding in this increment.

## Files

`docs/design/v3-dataset/ascend910b/`
