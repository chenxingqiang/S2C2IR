#!/usr/bin/env bash
# 4090 per-candidate measured-storage-v1 from @ssd_ntile_pipeline.
# One timed arm per legal signature (4/4). Two independent
# PREFETCH/PRESERVE sites. Does not grow F. Does not re-measure
# frozen 5A/5B. Does not change Cost v0.4, #69, or rewrite.
# Do not FileCheck microseconds. Do not store host/password/IP.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-./s2c2-cuda-run}
OUT=${2:-./v3-storage-measured-ntile-4090}
N_TILE=${S2C2_NTILE_N_TILE:-4194304}
K=${S2C2_CUDA_K:-32}
WARMUP=${S2C2_CUDA_WARMUP:-2}
REPS=${S2C2_CUDA_REPS:-5}
mkdir -p "$(dirname "$OUT")"
: > "${OUT}.log"
echo "sweep_storage_ntile_measured n-tile=$N_TILE k_ref=$K arms=4" >> "${OUT}.log"
"$BIN" --storage-ntile-measured --n="$N_TILE" --k="$K" \
  --warmup="$WARMUP" --reps="$REPS" --device=gpu 2>> "${OUT}.log"
REC=${S2C2_RECORD_PY:-"$HERE/../ascend/record_ascend.py"}
if [ ! -f "$REC" ]; then
  REC="$HERE/record_ascend.py"
fi
python3 "$REC" \
  --emit-storage-measured-from-ntile "${OUT}.log" \
  | tee "${OUT}.jsonl"
echo "sweep_storage_ntile_measured wrote ${OUT}.log ${OUT}.jsonl; not Cost; #69 untouched"
