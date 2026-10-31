// CUDA and Ascend CAP_SCHEMA_CONFIDENCE from the host recorders.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Do not FileCheck microseconds.
// RUN: python3 %S/../../runtime/record_q54_cacnf.py --print-q54-cacnf | FileCheck %s --check-prefix=Q54 --implicit-check-not=can-run-plan=yes
// Q54: q54-cacnf gate=query
// Q54: cap-confidence measured
// Q54: cap-confidence inferred
// Q54: cap-confidence arm_specific
// Q54: cap-confidence unknown
// Q54: q54-cacnf yes
// Q54: can-run-plan no
