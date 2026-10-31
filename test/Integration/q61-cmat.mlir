// CAP_MATMUL_DIMS stays 256, 512, and 1024. CAP_K stays 32.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Does not call run_analyzer.
// RUN: python3 %S/../../runtime/record_q61_cmat.py --print-q61-cmat | FileCheck %s --check-prefix=Q61 --implicit-check-not=can-run-plan=yes
// Q61: q61-cmat gate=query
// Q61: matmul-dim 256
// Q61: matmul-dim 512
// Q61: matmul-dim 1024
// Q61: cap-k 32
// Q61: q61-cmat yes
// Q61: can-run-plan no
