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

