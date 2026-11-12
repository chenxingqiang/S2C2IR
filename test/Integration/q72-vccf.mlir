// CUDA copy-contention fields from runtime/cuda/record_v3.VAL_CC_FIELDS.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Does not call run_analyzer.
// RUN: python3 %S/../../runtime/record_q72_vccf.py --print-q72-vccf | FileCheck %s --check-prefix=Q72 --implicit-check-not=can-run-plan=yes
// Q72: q72-vccf gate=query
// Q72: cc-field N
// Q72: cc-field k
// Q72: cc-field dim
// Q72: cc-field r
// Q72: cc-field T_silu_us
// Q72: cc-field T_matmul_us
// Q72: cc-field T_seq_us
// Q72: cc-field T_ovl_us
// Q72: cc-field T_silu_silu_us
// Q72: cc-field ovl_over_max
// Q72: cc-field ovl_over_sum
// Q72: cc-field mixed_verdict
// Q72: cc-field ss_over_max
// Q72: cc-field ss_over_sum
// Q72: cc-field same_verdict
// Q72: cc-field pair_relation
// Q72: cc-field observed_constraint
// Q72: q72-vccf yes
// Q72: can-run-plan no
