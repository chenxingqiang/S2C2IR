// CUDA memory-validation fields from runtime/cuda/record_v3.VAL_MEM_FIELDS.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Does not call run_analyzer.
// RUN: python3 %S/../../runtime/record_q70_vmfld.py --print-q70-vmfld | FileCheck %s --check-prefix=Q70 --implicit-check-not=can-run-plan=yes
// Q70: q70-vmfld gate=query
// Q70: mem-field N
// Q70: mem-field k
// Q70: mem-field pair
// Q70: mem-field residency
// Q70: mem-field r
// Q70: mem-field T_copy_us
// Q70: mem-field T_compute_us
// Q70: mem-field T_ovl_us
// Q70: mem-field ovl_over_max
// Q70: mem-field ovl_over_sum
// Q70: mem-field verdict
// Q70: mem-field extra_hb
// Q70: q70-vmfld yes
// Q70: can-run-plan no
