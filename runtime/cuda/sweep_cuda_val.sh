#!/usr/bin/env bash
# CUDA Validation V1 P0 sweep. Does not change Cost or A/B/C.
# Correctness is gated in the adapter. Do not FileCheck microseconds.
# Do not store host/password.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-./s2c2-cuda-run}
OUT=${2:-./v3-cuda-val}
CMD=(python3 "$HERE/record_v3.py" --cuda-val-sweep "$BIN" --out "$OUT")
if [[ -n "${S2C2_GIT_COMMIT:-}" ]]; then
  CMD+=(--git-commit "$S2C2_GIT_COMMIT")
fi
"${CMD[@]}"
python3 "$HERE/record_v3.py" --analyze-cuda-val "${OUT}.jsonl" --out "${OUT}-slices.csv"
