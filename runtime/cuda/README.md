# CUDA adapter runtime

Standalone timed stand-in of the three Pilot shapes. Not linked
into `s2c2-opt`. Host protocol (`--dry-run`) is
`s2c2-cuda-adapter` and does not need this directory.

```sh
# on a machine with nvcc
nvcc -O2 -std=c++17 runtime/cuda/s2c2_cuda_adapter.cu -o s2c2-cuda-run
# RTX 4090 example: add -arch=sm_89
./s2c2-cuda-run --func=all --device=gpu --n=16777216
./s2c2-cuda-run --func=all --device=cpu --n=16777216
./s2c2-cuda-run --func=all --n=16777216 --k=8 --provisioned
./s2c2-cuda-run --matched=all --device=gpu --n=16777216 --k=32
./s2c2-cuda-run --contend=all --device=gpu --n=16777216
S2C2_GIT_COMMIT=$(git rev-parse HEAD) ./runtime/cuda/sweep.sh ./s2c2-cuda-run ./v3-rerun
S2C2_GIT_COMMIT=$(git rev-parse HEAD) ./runtime/cuda/sweep_matched.sh ./s2c2-cuda-run ./v3-matched
S2C2_GIT_COMMIT=$(git rev-parse HEAD) ./runtime/cuda/sweep_contend.sh ./s2c2-cuda-run ./v3-contend
# writes JSONL/CSV; no host/password fields
# --matched does not change A/B/C bodies or Score_3
# 4090 records: docs/design/v3-dataset/v3-matched.jsonl
# calibration:  docs/design/v3-dataset/v3-matched-calibration.csv
```

Do not commit hostnames, accounts, or passwords.
Metadata records must not include them.
