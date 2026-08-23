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
