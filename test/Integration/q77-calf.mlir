// CUDA calibration fields from record_v3.CAL_FIELDS. Query only.
// No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Do not FileCheck microseconds.
// RUN: python3 %S/../../runtime/record_q77_calf.py --print-q77-calf | FileCheck %s --check-prefix=Q77 --implicit-check-not=can-run-plan=yes
// Q77: q77-calf gate=query
// Q77: cal-field N
// Q77: cal-field k
// Q77: cal-field T_seq_us
// Q77: cal-field T_ovl_us
// Q77: cal-field T_copy_us
// Q77: cal-field T_compute_us
// Q77: cal-field ratio
// Q77: cal-field gain_us
// Q77: cal-field ideal_us
// Q77: cal-field hidden_frac
// Q77: cal-field seq_over_sum
// Q77: cal-field ovl_over_max
// Q77: q77-calf yes
// Q77: can-run-plan no
