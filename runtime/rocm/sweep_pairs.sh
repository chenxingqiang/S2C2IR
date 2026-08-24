#!/usr/bin/env bash
# ROCm three-pair capability sweep. Does not change Cost or the scheduler.
# Do not FileCheck microseconds. Do not store host/password.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-./s2c2-rocm-run}
OUT=${2:-./v3-rocm-pairs}
mkdir -p "$(dirname "$OUT")"
"$BIN" --pairs ${S2C2_ROCM_N:+--n=$S2C2_ROCM_N} \
  ${S2C2_ROCM_K:+--k=$S2C2_ROCM_K} 2> "${OUT}.log"
python3 "$HERE/record_rocm.py" --print-workload-contract
echo "sweep_pairs wrote ${OUT}.log correctness protocol; project in PR-R2"
