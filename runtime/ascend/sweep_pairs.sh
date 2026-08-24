#!/usr/bin/env bash
# Ascend 910B three-pair capability sweep. Does not change Cost or the scheduler.
# Do not FileCheck microseconds. Do not store host/password.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-./s2c2-ascend-run}
OUT=${2:-./v3-ascend-pairs}
NS=${S2C2_ASCEND_NS:-4194304,16777216,67108864}
K=${S2C2_ASCEND_K:-32}
WARMUP=${S2C2_ASCEND_WARMUP:-2}
REPS=${S2C2_ASCEND_REPS:-5}
mkdir -p "$(dirname "$OUT")"
: > "${OUT}.log"
IFS=',' read -r -a sizes <<< "$NS"
for n in "${sizes[@]}"; do
  echo "sweep_pairs n=$n k=$K" >> "${OUT}.log"
  "$BIN" --pairs --n="$n" --k="$K" --warmup="$WARMUP" --reps="$REPS" \
    2>> "${OUT}.log"
done
python3 "$HERE/record_ascend.py" --project-pairs "${OUT}.log" --out "$(dirname "$OUT")"
echo "sweep_pairs wrote ${OUT}.log; project capability.jsonl topology only"
