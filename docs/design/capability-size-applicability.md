# Size-banded Capability Applicability

**Status:** compiler + catalog extension. Not Cost v0.4. Does **not**
open PR-R3, change `#69` `capability.jsonl`, auto-serialize 910B
`C||C` at `N≥32M`, add Schema v1 keys, or claim V3.

```text
Capability  ≠  DeviceProperty
Capability  =  f(hardware, pair, size, regime, residency, sync, resource)

Applicability (evidence covers this query)
    ≠
rewrite license (scheduler may flatten)
```

## Why this cut

`#72` measured 910B `C||C` at `r≈1`:

```text
N ≲ 16M          mixed / transition
N ∈ (16M, 32M)   N_transition
N ≥ 32M          serial / resource_contention
```

16M is a **boundary band** (`par/sum=0.867` mixed here; `#71` r=1
was serial). Do not freeze an exact `N*`. Do not upgrade this to a
global `C||C = serial` rule.

The `#69` scheduler catalog stays one underdetermined cell. This
file is the size-band **evidence overlay**, not a replacement.

## Records

Schema v1 fields only. Phase / license live in `note`:

```text
phase_band=mixed|transition|serial
regime_scope=r~1
rewrite_license=no
```

`size_range` is **payload bytes** (`N` floats × 4), not the harness
`N` label:

| N (floats) | payload | band | pair_relation | rewrite |
| ---------- | ------- | ---- | ------------- | ------- |
| 4M, 8M, 12M | 16MiB..48MiB | mixed | mixed | no |
| [16M, 32M) | 64MiB..127MiB | transition | underdetermined | no |
| 32M, 64M, 128M | 128MiB..512MiB | serial | serial / resource_contention | no |

Quote only **within r≈1**. Unmeasured N outside these closed ranges
does not hit a band → `underdetermined`.

File: `docs/design/v3-dataset/ascend910b/cc-size-applicability.jsonl`.

## Compiler

`--s2c2-capability-query` / `--s2c2-capability-schedule`:

```text
CapCatalog[pair] = list of cells
lookup = narrowest size_range covering the static payload
catalog query with no payload + several ranged cells
    → pair_relation=underdetermined, size_range=multiple
```

Applicability is unchanged:

```text
confidence = measured
AND synchronization matches
AND size_range is n/a or payload is inside the range
```

Rewrite (destructive flatten):

```text
applicable = yes
AND pair_relation = serial
AND rewrite_license ≠ no
```

Default `rewrite_license` is yes (4090 occupancy `C||C` with
`size_range=n/a` still flattens). 910B size bands set
`rewrite_license=no`, so a 128MiB `C||C` is queryable as serial
and **kept concurrent**.

Flipping that token to `yes` on a future measured band is the
licensed scheduler rule. That is not this increment.

## Query overlay (not Schema v1 keys)

Query JSON may print `phase_band` and `rewrite_license`. Those are
compiler applicability fields parsed from `note`. Frozen Schema v1
`FIELDS` stay 21 keys, `additionalProperties=false`.

## Out of scope

```text
Cost v0.4
PR-R3 / cross-hardware schedule rewrite
overwriting #69
auto-serialize N≥32M
D2D / P2P / ROCm
more 910B C||C random points
Schema v1 extra keys (phase_band, applicable, …)
```
