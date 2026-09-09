#!/usr/bin/env bash
# 4090 per-candidate measured-storage-v1 from @ssd_hierarchy_lifetime.
# One timed arm per legal signature. Does not grow F. Does not
# re-measure frozen pipeline S0/S1. Does not change Cost v0.4, #69,
# or rewrite. Do not FileCheck microseconds. Do not store
# host/password/IP.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-./s2c2-cuda-run}
OUT=${2:-./v3-storage-measured-hierarchy-4090}
N_TILE=${S2C2_HIER_N_TILE:-4194304}
K=${S2C2_CUDA_K:-32}
WARMUP=${S2C2_CUDA_WARMUP:-2}
REPS=${S2C2_CUDA_REPS:-5}
mkdir -p "$(dirname "$OUT")"
: > "${OUT}.log"
echo "sweep_storage_hierarchy_measured n-tile=$N_TILE k_ref=$K arms=8" >> "${OUT}.log"
"$BIN" --storage-hierarchy-measured --n="$N_TILE" --k="$K" \
  --warmup="$WARMUP" --reps="$REPS" --device=gpu 2>> "${OUT}.log"
python3 "$HERE/../ascend/record_ascend.py" \
  --emit-storage-measured-from-hierarchy "${OUT}.log" \
  | tee "${OUT}.jsonl"
echo "sweep_storage_hierarchy_measured wrote ${OUT}.log ${OUT}.jsonl; not Cost; #69 untouched"
