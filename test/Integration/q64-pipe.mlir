// RUN: python3 %S/../../runtime/record_q64_pipe.py --print-q64-pipe | FileCheck %s --check-prefix=Q64 --implicit-check-not=can-run-plan=yes
// Q64: q64-pipe gate=query
// Q64: pipe-tiles 8
// Q64: pipe-tile-set 4
// Q64: pipe-tile-set 8
// Q64: pipe-tile-set 16
// Q64: pipe-tile-set 32
// Q64: pipe-depth 1
// Q64: pipe-depth 2
// Q64: pipe-depth 3
// Q64: pipe-depth 4
// Q64: q64-pipe yes
// Q64: can-run-plan no
