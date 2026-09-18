#!/usr/bin/env bash
# Two-tile SSD prefetch || compute wall-clock on CUDA: T_evi / T_seq.
# Does not change Cost, the #69 catalog, or the SSD+MLP logs.
# Do not FileCheck microseconds. Do not store host/password/IP.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-./s2c2-cuda-run}
OUT=${2:-./v3-storage-pipeline-4090}
N_TILE=${S2C2_PIPE_N_TILE:-4194304}
N_CC=${S2C2_PIPE_N_CC:-33554432}
K=${S2C2_CUDA_K:-32}
WARMUP=${S2C2_CUDA_WARMUP:-2}
REPS=${S2C2_CUDA_REPS:-5}
mkdir -p "$(dirname "$OUT")"
: > "${OUT}.log"
echo "sweep_storage_pipeline n-tile=$N_TILE n-cc128=$N_CC k_ref=$K" >> "${OUT}.log"
"$BIN" --storage-pipeline --n="$N_TILE" --n-cc="$N_CC" --k="$K" \
  --warmup="$WARMUP" --reps="$REPS" --device=gpu 2>> "${OUT}.log"
python3 "$HERE/../ascend/record_ascend.py" --analyze-storage-pipeline "${OUT}.log"
echo "sweep_storage_pipeline wrote ${OUT}.log; SSD+MLP logs untouched; not Cost"
