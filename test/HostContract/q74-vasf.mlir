// CUDA VAL_ASYNC_FIELDS from runtime/cuda/record_v3.py.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Does not call run_analyzer.
// RUN: python3 %S/../../runtime/record_q74_vasf.py --print-q74-vasf | FileCheck %s --check-prefix=Q74 --implicit-check-not=can-run-plan=yes
// Q74: q74-vasf gate=query
// Q74: async-field N
// Q74: async-field k
// Q74: async-field r
// Q74: async-field T_copy_us
// Q74: async-field T_compute_us
// Q74: async-field T_life_sync_us
// Q74: async-field T_life_async_us
// Q74: async-field T_hb_us
// Q74: async-field sync_over_async
// Q74: async-field hb_over_async
// Q74: async-field observed_constraint
// Q74: async-field extra_hb
// Q74: q74-vasf yes
// Q74: can-run-plan no
