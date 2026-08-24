#!/usr/bin/env bash
# Ascend 910B C||C r-sweep. Does not change Cost, #69 catalog, or the scheduler.
# Do not FileCheck microseconds. Do not store host/password.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-./s2c2-ascend-run}
OUT=${2:-./v3-ascend-cc-phase}
NS=${S2C2_ASCEND_NS:-4194304,16777216,67108864}
K=${S2C2_ASCEND_K:-32}
RS=${S2C2_ASCEND_RS:-0.5,0.75,1,1.5,2}
WARMUP=${S2C2_ASCEND_WARMUP:-2}
REPS=${S2C2_ASCEND_REPS:-5}
mkdir -p "$(dirname "$OUT")"
: > "${OUT}.log"
IFS=',' read -r -a sizes <<< "$NS"
for n in "${sizes[@]}"; do
  echo "sweep_cc_phase n=$n k_ref=$K r=$RS" >> "${OUT}.log"
  "$BIN" --cc-phase --n="$n" --k="$K" --r="$RS" --warmup="$WARMUP" \
    --reps="$REPS" 2>> "${OUT}.log"
done
python3 "$HERE/record_ascend.py" --analyze-cc-phase "${OUT}.log"
echo "sweep_cc_phase wrote ${OUT}.log; #69 catalog untouched; r3-gate closed"
