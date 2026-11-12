// RUN: python3 %S/../../runtime/record_q88_compop.py --print-q88-compop | FileCheck %s --check-prefix=Q88 --implicit-check-not=can-run-plan=yes
// Q88: q88-compop gate=query
// Q88: comp-op matmul
// Q88: comp-op elemwise
// Q88: comp-op gated_mlp
// Q88: q88-compop yes
// Q88: can-run-plan no
