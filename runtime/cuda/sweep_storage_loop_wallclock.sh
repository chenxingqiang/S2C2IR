#!/usr/bin/env bash
# 3I scf.for software-pipeline wall-clock on CUDA: T_evi / T_seq.
# Static trip=2 after prologue. Not arbitrary runtime-N. Not Cost.
# Does not change Cost, the #69 catalog, or the SSD+MLP / 3F logs.
# Do not FileCheck microseconds. Do not store host/password/IP.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-./s2c2-cuda-run}
OUT=${2:-./v3-storage-loop-wallclock-4090}
N_TILE=${S2C2_LOOP_N_TILE:-4194304}
K=${S2C2_CUDA_K:-32}
WARMUP=${S2C2_CUDA_WARMUP:-2}
REPS=${S2C2_CUDA_REPS:-5}
mkdir -p "$(dirname "$OUT")"
: > "${OUT}.log"
echo "sweep_storage_loop_wallclock n-tile=$N_TILE tiles=3 trip=2 k_ref=$K" >> "${OUT}.log"
"$BIN" --storage-loop-wallclock --n="$N_TILE" --k="$K" \
  --warmup="$WARMUP" --reps="$REPS" --device=gpu 2>> "${OUT}.log"
python3 "$HERE/../ascend/record_ascend.py" --analyze-storage-loop-wallclock "${OUT}.log"
echo "sweep_storage_loop_wallclock wrote ${OUT}.log; 3F/SSD+MLP logs untouched; not Cost"
