// CUDA PHASE_FIELDS from runtime/cuda/record_v3.py.
// This lit test is not in check-host. No semantic cut. can-run-plan stays no.
// Do not FileCheck microseconds. This file does not require s2c2-opt.
// RUN: python3 %S/../../runtime/record_q76_phf.py --print-q76-phf | FileCheck %s --check-prefix=Q76 --implicit-check-not=can-run-plan=yes
// Q76: q76-phf gate=query
// Q76: phase-field N
// Q76: phase-field k
// Q76: phase-field r_target
// Q76: phase-field r_achieved
// Q76: phase-field T_seq_us
// Q76: phase-field T_ovl_us
// Q76: phase-field T_copy_us
// Q76: phase-field T_compute_us
// Q76: phase-field ovl_over_max
// Q76: phase-field ovl_over_sum
// Q76: phase-field hidden_frac
// Q76: phase-field dominance
// Q76: phase-field overlap
// Q76: q76-phf yes
// Q76: can-run-plan no
