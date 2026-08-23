#!/usr/bin/env bash
# V3 campaign sweep. Does not change Cost. Do not FileCheck output.
set -euo pipefail
BIN=${1:-./s2c2-cuda-run}
for n in 4194304 16777216 67108864; do
  for k in 1 8; do
    for prov in "" "--provisioned"; do
      echo "=== n=$n k=$k ${prov:-} ==="
      "$BIN" --func=all --device=gpu --n="$n" --k="$k" $prov
    done
  done
done
