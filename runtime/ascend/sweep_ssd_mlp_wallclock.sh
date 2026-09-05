#!/usr/bin/env bash
# Complete SSD+MLP program wall-clock: T_evi / T_seq.
# Does not change Cost, the #69 catalog, or the stage A/B license.
# Do not FileCheck microseconds. Do not store host/password/IP.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-./s2c2-ascend-run}
OUT=${2:-./v3-ssd-mlp-wallclock}
N_HTOD=${S2C2_SSD_MLP_N_HTOD:-22528000}
N_CC=${S2C2_SSD_MLP_N_CC:-33554432}
K=${S2C2_ASCEND_K:-32}
WARMUP=${S2C2_ASCEND_WARMUP:-2}
REPS=${S2C2_ASCEND_REPS:-5}
mkdir -p "$(dirname "$OUT")"
: > "${OUT}.log"
echo "sweep_ssd_mlp_wallclock n-htod=$N_HTOD n-cc=$N_CC k_ref=$K" >> "${OUT}.log"
"$BIN" --ssd-mlp-wallclock --n="$N_HTOD" --n-cc="$N_CC" --k="$K" \
  --warmup="$WARMUP" --reps="$REPS" 2>> "${OUT}.log"
python3 "$HERE/record_ascend.py" --analyze-ssd-mlp-wallclock "${OUT}.log"
echo "sweep_ssd_mlp_wallclock wrote ${OUT}.log; #69 catalog untouched; not Cost"
