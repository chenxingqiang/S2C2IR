#!/usr/bin/env bash
# CUDA Validation V2 P0 sweep: pinned vs pageable.
# Does not change Cost, A/B/C, or V1 --cuda-val timed bodies.
# Correctness is gated in the adapter. Do not FileCheck microseconds.
# Do not store host/password.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-./s2c2-cuda-run}
OUT=${2:-./v3-cuda-mem}
CMD=(python3 "$HERE/record_v3.py" --cuda-val-mem-sweep "$BIN" --out "$OUT")
if [[ -n "${S2C2_GIT_COMMIT:-}" ]]; then
  CMD+=(--git-commit "$S2C2_GIT_COMMIT")
fi
"${CMD[@]}"
python3 "$HERE/record_v3.py" --analyze-cuda-val-mem "${OUT}.jsonl" \
  --out "${OUT}-slices.csv"
