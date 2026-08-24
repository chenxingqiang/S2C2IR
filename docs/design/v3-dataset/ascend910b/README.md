# Ascend 910B Capability catalog (PR-R2)

Measured Capability Schema v1 cells for three pairs on one
Ascend 910B. Not Cost v0.4. Not V3. Not a scheduler change.

```text
Same Schema v1 as docs/design/v3-dataset/v3-cap-schema-4090.jsonl
hardware_id = ascend910b:ascend
confidence  = measured
```

| File | Role |
| ---- | ---- |
| `capability.jsonl` | one projected cell per pair |
| `pairs.csv` | per-(N,k) classifier inputs (not FileChecked) |

Grid: `N ∈ {4M,16M,64M}` floats, `k=32`, pinned host, named streams,
`T_pair = completion(s0,s1)`. aclnn executors primed before timed
samples.

Per-size topology (classifier slack unchanged):

| N | `C\|\|HtoD` | `C\|\|C` | `HtoD\|\|DtoH` |
| -- | --- | --- | --- |
| 4M | mixed | mixed | mixed |
| 16M | parallel | serial | mixed |
| 64M | mixed | serial | mixed |

Projected cells (`size_range=16MiB..256MiB`):

| Pair | pair_relation | observed_constraint |
| ---- | ------------- | ------------------- |
| `C\|\|HtoD` | underdetermined | none |
| `C\|\|C` | underdetermined | none |
| `HtoD\|\|DtoH` | mixed | none |

Sizes that disagree stay `underdetermined`. That is the catalog
answer, not a majority vote.

Do not FileCheck microseconds. Do not compare 4090 μs to 910B μs.
Do not store host / password / IP.

`HtoD||DtoH` keeps `direction=host_to_device` because that is the
frozen Schema v1 pair-record convention used by the 4090 catalog,
not a 910B-specific interpretation.

Pinned vs pageable (R4): `mem.log`, `mem-slices.csv`, `mem.jsonl`.
`counterexamples=0`. Extra HB was not observed. Rate may differ;
that is not a Schedule rewrite. Memory records use
`size_range=4MiB..64MiB` (`measured sizes = 4MiB,16MiB,64MiB`).
Cross-vendor schedule (PR-R3) is not this catalog: `C||C` is not
a single parallel cell.
