// CUDA validation fields from runtime/cuda/record_v3.VAL_FIELDS.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Does not call run_analyzer.
// RUN: python3 %S/../../runtime/record_q67_vfld.py --print-q67-vfld | FileCheck %s --check-prefix=Q67 --implicit-check-not=can-run-plan=yes
// Q67: q67-vfld gate=query
// Q67: val-field N
// Q67: val-field k
// Q67: val-field stream
// Q67: val-field r
// Q67: val-field T_copy_us
// Q67: val-field T_compute_us
// Q67: val-field T_seq_us
// Q67: val-field T_ovl_us
// Q67: val-field ovl_over_max
// Q67: val-field ovl_over_sum
// Q67: val-field verdict
// Q67: val-field extra_hb
// Q67: q67-vfld yes
// Q67: can-run-plan no
