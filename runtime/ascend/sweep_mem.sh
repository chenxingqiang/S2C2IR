#!/usr/bin/env bash
# 910B pinned vs pageable sweep. Does not change Cost or the pair catalog.
# Do not FileCheck microseconds. Do not store host/password.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-./s2c2-ascend-run}
OUT=${2:-./v3-ascend-mem}
NS=${S2C2_ASCEND_NS:-4194304,16777216,67108864}
WARMUP=${S2C2_ASCEND_WARMUP:-2}
REPS=${S2C2_ASCEND_REPS:-5}
mkdir -p "$(dirname "$OUT")"
: > "${OUT}.log"
IFS=',' read -r -a sizes <<< "$NS"
for n in "${sizes[@]}"; do
  echo "sweep_mem n=$n k=calibrate" >> "${OUT}.log"
  "$BIN" --mem --n="$n" --k=0 --warmup="$WARMUP" --reps="$REPS" \
    2>> "${OUT}.log"
done
python3 "$HERE/record_ascend.py" --analyze-mem "${OUT}.log"
echo "sweep_mem wrote ${OUT}.log; topology only"
