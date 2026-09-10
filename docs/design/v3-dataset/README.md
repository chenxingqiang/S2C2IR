# V3 4090 rerun dataset

36 GPU points from one RTX 4090 under the metadata protocol.
Not a FileCheck lock. Not V3 validated. No host / password fields.

| File | Role |
| ---- | ---- |
| `v3-rerun.jsonl` | one record per point |
| `v3-rerun.csv` | same columns |

`git_commit` is the protocol tree. Adapter A/B/C bodies are
unchanged from `40f8a2b`. `clock_state` is a pre-sweep
`nvidia-smi` snapshot (may be idle P-state).

`cuda_runtime` is `cudaRuntimeGetVersion()` from the
measurement binary, not the `nvidia-smi` CUDA Version banner.

Capability-matrix records (`v3-cap.jsonl`, 60 points) reuse the
same columns. `score3` is empty. Derived pair table:
`v3-cap-pairs.csv`. Not Cost v0.4.

C∥HtoD phase-diagram records (`v3-phase.jsonl`, 66 points)
reuse the same columns. Derived slices: `v3-phase-slices.csv`.

C∥HtoD pipeline-depth records (`v3-pipe.jsonl`, 18 points)
reuse the same columns. Derived slices: `v3-pipe-slices.csv`.

C∥HtoD pipeline-tiles sanity records (`v3-pipe-tiles.jsonl`,
72 points) reuse the same columns. Case names carry the
tiles count (`pipe-t{T}-*`). Derived slices:
`v3-pipe-tiles-slices.csv`.

CUDA Validation V1 P0 records (`v3-cuda-val.jsonl`) reuse
the same columns after the 4090 sweep. Derived:
`v3-cuda-val-slices.csv`. Not Cost v0.4.

CUDA Validation V2 P0 pinned vs pageable records
(`v3-cuda-mem.jsonl`) reuse the same columns after the
4090 sweep. Derived: `v3-cuda-mem-slices.csv`. Does not
change V1 `--cuda-val` bodies. Not Cost v0.4.

C_light ∥ C_heavy records (`v3-cuda-clight.jsonl`) reuse
the same columns after the 4090 sweep. Derived:
`v3-cuda-clight-slices.csv`. Does not change V1/V2 timed
bodies. Not Cost v0.4.

CUDA Validation V2 P1 async-alloc records
(`v3-cuda-async.jsonl`) reuse the same columns after the
4090 sweep. Derived: `v3-cuda-async-slices.csv`. Does not
change V1 / V2 mem / C_light timed bodies. Not Cost v0.4.

Hardware-neutral Capability Schema v1 catalog
(`v3-cap-schema-4090.jsonl`) is the compiler input for
`--s2c2-capability-query` / `--s2c2-capability-schedule`.
Synthetic NPU demo cells (`v3-cap-schema-npu-demo.jsonl`)
are **not measured**. Not Cost v0.4.

Ascend 910B uses the **same** Capability Schema v1. Measured
catalog: `docs/design/v3-dataset/ascend910b/` (pairs + R4 mem).
Topology only; do not FileCheck microseconds.

Complete SSD+MLP program wall-clock logs:
`ssd-mlp-wallclock.log` (910B) and `ssd-mlp-wallclock-4090.log`
(4090). Both `measured=yes`. Two-tile SSD prefetch || compute:
`storage-pipeline-4090.log` (4090, `measured=yes`). 3I loop
program wall-clock: `storage-loop-wallclock-4090.log` (4090)
and `storage-loop-wallclock.log` (910B). Both `measured=yes`.
Not Cost v0.4.
`#69` untouched. Do not FileCheck microseconds. Do not compare
4090 μs to 910B μs.

Batch index of every retained hardware artifact:
[`hardware-ledger.jsonl`](hardware-ledger.jsonl). Check together
with `python3 runtime/record_hw_ledger.py --check-hw-ledger`.
Do not move campaign files. Do not FileCheck microseconds.

Compiler-facing Evidence DB (Phase 6B):
[`evidence-db.jsonl`](evidence-db.jsonl), schema
`s2c2.evidence.v1`. Normalized from the frozen
`storage-measured-v1*.jsonl` tables. Not the hardware
ledger. Check with
`python3 runtime/record_evidence.py --check-evidence-db`.
Do not FileCheck microseconds.

Phase 6C capacity design witness (not measured, not the
ledger): [`storage-capacity-4tile.jsonl`](storage-capacity-4tile.jsonl)
and [`storage-capacity-2tile-fit.jsonl`](storage-capacity-2tile-fit.jsonl),
[`storage-capacity-3tile-tight.jsonl`](storage-capacity-3tile-tight.jsonl).
Check with `python3 runtime/record_capacity.py --analyze-storage-capacity`.
Consumer query: `python3 runtime/record_capacity.py --query-capacity-plan`.
Selection: `--query-capacity-plan ... --capacity-policy=s0`.
Measured ranking (fixtures, not a campaign, not Evidence DB):
[`storage-capacity-measured-4tile.jsonl`](storage-capacity-measured-4tile.jsonl)
(ArgMin coincides with s0),
[`storage-capacity-measured-4tile-argmin.jsonl`](storage-capacity-measured-4tile-argmin.jsonl)
(ArgMin ≠ s0),
[`storage-capacity-measured-4tile-one.jsonl`](storage-capacity-measured-4tile-one.jsonl)
(needs two usable records),
[`storage-capacity-measured-4tile-wrong-profile.jsonl`](storage-capacity-measured-4tile-wrong-profile.jsonl),
[`storage-capacity-measured-4tile-wrong-workload.jsonl`](storage-capacity-measured-4tile-wrong-workload.jsonl),
[`storage-capacity-measured-4tile-cross-workload.jsonl`](storage-capacity-measured-4tile-cross-workload.jsonl)
(same candidate, different workload must not reuse),
[`storage-capacity-measured-4tile-tie.jsonl`](storage-capacity-measured-4tile-tie.jsonl)
(equal times pick earliest \(F\)),
[`storage-capacity-measured-4tile-dup.jsonl`](storage-capacity-measured-4tile-dup.jsonl)
(duplicate scoped identity is rejected). Matcher is
`profile + workload_class + candidate_identity`. Schema
`s2c2.measured_capacity_cost.v1`. `workload_class` here is
the occupancy witness, not an Evidence DB field. Do not
FileCheck microseconds. No `measurement_revision` on this
v1 table.
The capacity rewrite-license gate (`s2c2.capacity_license.v1`)
is a printed query contract, not a dataset file.
TRANSFER restore sources (optional, not occupancy, not a
new \(F\) member):
[`storage-capacity-4tile-transfer-restore.jsonl`](storage-capacity-4tile-transfer-restore.jsonl).
Same 4-tile \(F_{\mathrm{capacity}}\); `closed=yes` still
`rewrite-license=no`. The license predicate
(`s2c2.capacity_predicate.v1`) is a printed query
contract: `necessary=yes` on this fixture, `sufficient=no`.
Source-data proofs (optional, not occupancy, not a new
\(F\) member):
[`storage-capacity-4tile-source-data.jsonl`](storage-capacity-4tile-source-data.jsonl).
Same \(F_{\mathrm{capacity}}\); `source-data=yes` still
`usable=no` `sufficient=no` `rewrite-license=no`. Replica
scope is explicit (`replica=ssd`,
`witness=spec-unmutated-cover`, `scope=occupancy-live`).
Check with
`python3 runtime/record_capacity.py --print-capacity-sourcedata-contract`.

