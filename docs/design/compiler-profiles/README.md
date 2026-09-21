# Compiler Profile v1

**Status:** Phase 3D. Compiler configuration, not a CapabilityRecord
and not Cost v0.4. Does **not** overwrite `#69` or add grid points.

The optimizer consumes **profile + evidence**. It does not read
adapter logs, wall-clock dumps, or benchmark scripts.

```text
measurement
    ↓
evidence database (CapabilityRecord JSONL / builtin projection)
    ↓
compiler profile
    ↓
s2c2-opt
```

## Schema

JSON object. `schema` is `s2c2.compiler_profile.v1`.

| Field | Type | Meaning |
| ----- | ---- | ------- |
| `profile` | string | Named id: `rtx4090`, `910B`, `unknown` |
| `device` | string | Hardware id used for evidence matching |
| `evidence` | string or array | Builtin id, JSONL path, or inline cells |

`evidence` string forms:

```text
builtin:rtx4090
builtin:910B
builtin:npu-demo
docs/design/v3-dataset/ascend910b/cc-size-applicability.jsonl
```

Relative JSONL paths resolve against the profile file directory,
then `S2C2_SOURCE_DIR`.

Inline cells are the compiler-facing subset. They are **not**
Schema v1 pair rows (no extra `acl_*` / `davinci_*` columns):

```json
{
  "pair": "C||C",
  "size_range": "128MiB..512MiB",
  "pair_relation": "serial",
  "observed_constraint": "resource_contention",
  "rewrite_license": true,
  "confidence": "measured"
}
```

Empty `evidence` (`[]` or omitted) is the `unknown` profile:
no licensed rewrite.

## Named profiles

| Name | Device | Evidence |
| ---- | ------ | -------- |
| `rtx4090` | `rtx4090` | builtin 4090 catalog |
| `910B` / `ascend910b` | `ascend910b:ascend` | overlay projection of `cc-size-applicability.jsonl` |
| `unknown` | `unknown` | empty |

`910B` is the size-banded overlay, **not** `#69` `capability.jsonl`.
`#69` `C||C` stays `underdetermined`. Pass `--evidence=` to that
catalog to keep every `C||C`.

Shipped files:

```text
docs/design/compiler-profiles/rtx4090.json
docs/design/compiler-profiles/910B.json
docs/design/compiler-profiles/910B-overlay.json
docs/design/compiler-profiles/unknown.json
```
