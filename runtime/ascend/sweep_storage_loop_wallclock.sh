#!/usr/bin/env bash
# 3I scf.for software-pipeline wall-clock on Ascend: T_evi / T_seq.
# Static trip=2 after prologue. Not arbitrary runtime-N. Not Cost.
# Does not change Cost, the #69 catalog, or the SSD+MLP / 3F logs.
# Do not FileCheck microseconds. Do not store host/password/IP.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-./s2c2-ascend-run}
OUT=${2:-./v3-storage-loop-wallclock}
N_TILE=${S2C2_LOOP_N_TILE:-4194304}
K=${S2C2_ASCEND_K:-32}
WARMUP=${S2C2_ASCEND_WARMUP:-2}
REPS=${S2C2_ASCEND_REPS:-5}
mkdir -p "$(dirname "$OUT")"
: > "${OUT}.log"
echo "sweep_storage_loop_wallclock n-tile=$N_TILE tiles=3 trip=2 k_ref=$K" >> "${OUT}.log"
"$BIN" --storage-loop-wallclock --n="$N_TILE" --k="$K" \
  --warmup="$WARMUP" --reps="$REPS" 2>> "${OUT}.log"
python3 "$HERE/record_ascend.py" --analyze-storage-loop-wallclock "${OUT}.log"
echo "sweep_storage_loop_wallclock wrote ${OUT}.log; #69 catalog untouched; not Cost"
