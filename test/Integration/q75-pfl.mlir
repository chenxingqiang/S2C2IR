// CUDA PIPE_FIELDS from runtime/cuda/record_v3.py.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Does not call run_analyzer.
// RUN: python3 %S/../../runtime/record_q75_pfl.py --print-q75-pfl | FileCheck %s --check-prefix=Q75 --implicit-check-not=can-run-plan=yes
// Q75: q75-pfl gate=query
// Q75: pipe-field N
// Q75: pipe-field k
// Q75: pipe-field tiles
// Q75: pipe-field r_tile
// Q75: pipe-field T_copy_us
// Q75: pipe-field T_compute_us
// Q75: pipe-field T_d1_us
// Q75: pipe-field T_d2_us
// Q75: pipe-field T_d3_us
// Q75: pipe-field T_d4_us
// Q75: pipe-field speedup_d2
// Q75: pipe-field speedup_d3
// Q75: pipe-field speedup_d4
// Q75: pipe-field ideal
// Q75: pipe-field T_ideal_pipe_us
// Q75: pipe-field sat_d4_over_d2
// Q75: q75-pfl yes
// Q75: can-run-plan no
