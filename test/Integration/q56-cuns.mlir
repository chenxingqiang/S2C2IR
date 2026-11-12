// CUDA N sizes from record_v3.NS. Query only.
// No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Do not FileCheck microseconds.
// RUN: python3 %S/../../runtime/record_q56_cuns.py --print-q56-cuns | FileCheck %s --check-prefix=Q56 --implicit-check-not=can-run-plan=yes
// Q56: q56-cuns gate=query
// Q56: cuda-n 4194304
// Q56: cuda-n 16777216
// Q56: cuda-n 67108864
// Q56: q56-cuns yes
// Q56: can-run-plan no
