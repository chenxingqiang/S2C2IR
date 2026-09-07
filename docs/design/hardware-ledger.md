# Hardware measurement ledger

**Status:** index + batch host check. Not Cost v0.4. Does
**not** move existing logs, densify Capability grids, overwrite
`#69`, FileCheck microseconds, or invent `T_evi/T_seq`.

```text
Hardware evidence stays where it was measured.
The ledger only names those files so they can be
checked together later.
```

```text
Ledger              ≠  Capability Schema v1
Ledger status       ≠  a rewrite license
device-absent       ≠  measured=no invented ratio
npu-demo inferred   ≠  this ledger
```

## Why this cut

4090 campaigns, 910B catalogs, the licensed `C||C` A/B, and
the SSD+MLP program wall-clock currently live as separate
artifacts with separate lit files. A later on-device session
should fill pending slots **in place** and re-run one check,
not open a new dataset layout.

```text
record  →  keep the original path
check   →  all ledger rows in one host test
pending →  device-absent until a real run
```

## Ledger

File: `docs/design/v3-dataset/hardware-ledger.jsonl`

Each row is an index record, not a Capability cell.

| Field | Meaning |
| ----- | ------- |
| `id` | stable campaign id |
| `hardware` | `rtx4090` / `ascend910b` |
| `kind` | `catalog` / `overlay` / `campaign` / `program` |
| `status` | `measured` / `device-absent` |
| `path` | repo-relative artifact |
| `tool` | `cuda` / `ascend` / `none` |
| `analyze` | existing `--analyze-*` name, or empty |
| `catalog_role` | `catalog-69` / `overlay` / `compiler-4090` / `campaign` / `pending-program` |
| `note` | free text; no host / password / IP |
| `cost` | `unchanged` |
| `semantics` | `unchanged` |

`#69` `capability.jsonl` remains the pair catalog.
`cc-size-applicability.jsonl` remains the overlay.
`ssd-mlp-wallclock.log` remains `device-absent` until a
4090 / 910B run overwrites **that same path**.

## Batch check

```sh
python3 runtime/record_hw_ledger.py --print-hw-ledger-contract
python3 runtime/record_hw_ledger.py --check-hw-ledger
```

The checker:

1. Loads the ledger. Extra Schema v1 / vendor keys are rejected.
2. Confirms every `path` exists.
3. Scans artifacts for `password` (and does not store host/IP).
4. Runs the existing analyzer for rows that declare one.
   Analyzer stdout is not FileChecked.
5. Queries `#69` `C||C` and requires `underdetermined`.
6. Prints tokens only: counts, `catalog-69=underdetermined`,
   `ssd-mlp-wallclock=device-absent`, `cost=unchanged`.

Do not FileCheck microseconds. Do not compare 4090 μs to 910B μs.

A later device run:

```sh
runtime/ascend/sweep_ssd_mlp_wallclock.sh ./s2c2-ascend-run \
  docs/design/v3-dataset/ssd-mlp-wallclock
python3 runtime/record_hw_ledger.py --check-hw-ledger
```

Then update that ledger row to `status=measured`. Until then
the batch test must keep `device-absent`.

## Out of scope

```text
Cost v0.4
new Capability grid points
overwriting #69
moving v3-dataset files
ROCm / D2D / P2P
FileCheck of microseconds
```
