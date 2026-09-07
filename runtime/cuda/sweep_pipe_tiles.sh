#!/usr/bin/env bash
# C||HtoD pipeline tiles sanity sweep. Does not change Cost or A/B/C.
# Does not change --pipe default tiles=8. Do not FileCheck microseconds.
# Do not store host/password.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
BIN=${1:-./s2c2-cuda-run}
OUT=${2:-./v3-pipe-tiles}
CMD=(python3 "$HERE/record_v3.py" --pipe-tiles-sweep "$BIN" --out "$OUT")
if [[ -n "${S2C2_GIT_COMMIT:-}" ]]; then
  CMD+=(--git-commit "$S2C2_GIT_COMMIT")
fi
"${CMD[@]}"
python3 "$HERE/record_v3.py" --analyze-pipe-tiles "${OUT}.jsonl" --out "${OUT}-slices.csv"
