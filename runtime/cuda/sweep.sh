#!/usr/bin/env bash
# V3 campaign sweep with metadata records. Does not change Cost.
# Do not FileCheck microseconds. Do not store host/password.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-./s2c2-cuda-run}
OUT=${2:-./v3-rerun}
CMD=(python3 "$HERE/record_v3.py" --sweep "$BIN" --out "$OUT")
if [[ -n "${S2C2_GIT_COMMIT:-}" ]]; then
  CMD+=(--git-commit "$S2C2_GIT_COMMIT")
fi
"${CMD[@]}"
python3 "$HERE/record_v3.py" --analyze "${OUT}.jsonl"
