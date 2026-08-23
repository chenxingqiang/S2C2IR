#!/usr/bin/env bash
# Two-HtoD contention sweep. Does not change Cost, A/B/C, or --matched.
# Do not FileCheck microseconds. Do not store host/password.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-./s2c2-cuda-run}
OUT=${2:-./v3-contend}
CMD=(python3 "$HERE/record_v3.py" --contend-sweep "$BIN" --out "$OUT")
if [[ -n "${S2C2_GIT_COMMIT:-}" ]]; then
  CMD+=(--git-commit "$S2C2_GIT_COMMIT")
fi
"${CMD[@]}"
python3 "$HERE/record_v3.py" --analyze-contend "${OUT}.jsonl"
