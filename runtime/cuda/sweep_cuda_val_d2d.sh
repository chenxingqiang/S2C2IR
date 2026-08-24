#!/usr/bin/env bash
# CUDA Validation D2D sweep: same-device DeviceToDevice vs HtoD.
# Does not change Cost, A/B/C, V1 --cuda-val, V2 --cuda-val-mem,
# --cuda-val-cc, or --cuda-val-async bodies.
# Correctness is gated in the adapter. Do not FileCheck microseconds.
# Do not store host/password. P2P is out of this increment.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-./s2c2-cuda-run}
OUT=${2:-./v3-cuda-d2d}
CMD=(python3 "$HERE/record_v3.py" --cuda-val-d2d-sweep "$BIN" --out "$OUT")
if [[ -n "${S2C2_GIT_COMMIT:-}" ]]; then
  CMD+=(--git-commit "$S2C2_GIT_COMMIT")
fi
"${CMD[@]}"
python3 "$HERE/record_v3.py" --analyze-cuda-val-d2d "${OUT}.jsonl" \
  --out "${OUT}-slices.csv"
