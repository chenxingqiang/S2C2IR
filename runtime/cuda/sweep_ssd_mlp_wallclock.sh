#!/usr/bin/env bash
# Complete SSD+MLP program wall-clock on CUDA: T_evi / T_seq.
# Does not change Cost, the #69 catalog, or the 910B log.
# Do not FileCheck microseconds. Do not store host/password/IP.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-./s2c2-cuda-run}
OUT=${2:-./v3-ssd-mlp-wallclock-4090}
N_HTOD=${S2C2_SSD_MLP_N_HTOD:-22528000}
N_CC=${S2C2_SSD_MLP_N_CC:-33554432}
K=${S2C2_CUDA_K:-32}
WARMUP=${S2C2_CUDA_WARMUP:-2}
REPS=${S2C2_CUDA_REPS:-5}
mkdir -p "$(dirname "$OUT")"
: > "${OUT}.log"
echo "sweep_ssd_mlp_wallclock n-htod=$N_HTOD n-cc=$N_CC k_ref=$K" >> "${OUT}.log"
"$BIN" --ssd-mlp-wallclock --n="$N_HTOD" --n-cc="$N_CC" --k="$K" \
  --warmup="$WARMUP" --reps="$REPS" --device=gpu 2>> "${OUT}.log"
python3 "$HERE/../ascend/record_ascend.py" --analyze-ssd-mlp-wallclock "${OUT}.log"
echo "sweep_ssd_mlp_wallclock wrote ${OUT}.log; 910B log untouched; not Cost"
