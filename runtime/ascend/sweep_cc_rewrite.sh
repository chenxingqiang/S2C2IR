#!/usr/bin/env bash
# Ascend 910B C||C sequential vs concurrent A/B at r≈1, N>=32M.
# Does not change Cost, the #69 catalog, or R3. Do not FileCheck μs.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-./s2c2-ascend-run}
OUT=${2:-./v3-ascend-cc-rewrite}
NS=${S2C2_ASCEND_NS:-33554432,67108864,134217728}
K=${S2C2_ASCEND_K:-32}
WARMUP=${S2C2_ASCEND_WARMUP:-2}
REPS=${S2C2_ASCEND_REPS:-5}
mkdir -p "$(dirname "$OUT")"
: > "${OUT}.log"
IFS=',' read -r -a sizes <<< "$NS"
for n in "${sizes[@]}"; do
  echo "sweep_cc_rewrite n=$n k_ref=$K r=1" >> "${OUT}.log"
  "$BIN" --cc-rewrite --n="$n" --k="$K" --r=1 --warmup="$WARMUP" \
    --reps="$REPS" 2>> "${OUT}.log"
done
python3 "$HERE/record_ascend.py" --analyze-cc-rewrite "${OUT}.log"
echo "sweep_cc_rewrite wrote ${OUT}.log; #69 catalog untouched; r3-gate closed"
