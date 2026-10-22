// RUN: python3 %S/../../runtime/record_q37_occmap.py --print-q37-occmap | FileCheck %s --check-prefix=Q37 --implicit-check-not=can-run-plan=yes
// Q37: q37-occmap gate=query
// Q37: occupancy-map-count 13
// Q37: unknown-scope-maps evidence.scope-mismatch
// Q37: q37-occmap yes
// Q37: can-run-plan no
