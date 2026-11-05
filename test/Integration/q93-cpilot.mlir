// CUDA kPilots from AdapterContract.h bound to record_v3.CASES. Query only.
// No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Do not FileCheck microseconds.
// RUN: python3 %S/../../runtime/record_q93_cpilot.py --print-q93-cpilot | FileCheck %s --check-prefix=Q93 --implicit-check-not=can-run-plan=yes
// Q93: q93-cpilot gate=query
// Q93: pilot a pilot_a_ssd_hbm_compute 130
// Q93: pilot b pilot_b_compute_par_comm 128
// Q93: pilot c pilot_c_pipeline_three_stage 163
// Q93: q93-cpilot yes
// Q93: can-run-plan no
