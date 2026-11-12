// CUDA PIPE_ARMS from runtime/cuda/record_v3.py.
// This lit test is not in check-host. No semantic cut. can-run-plan stays no.
// Do not FileCheck microseconds. This file does not require s2c2-opt.
// RUN: python3 %S/../../runtime/record_q65_parm.py --print-q65-parm | FileCheck %s --check-prefix=Q65 --implicit-check-not=can-run-plan=yes
// Q65: q65-parm gate=query
// Q65: pipe-arm pipe-copy
// Q65: pipe-arm pipe-compute
// Q65: pipe-arm pipe-d1
// Q65: pipe-arm pipe-d2
// Q65: pipe-arm pipe-d3
// Q65: pipe-arm pipe-d4
// Q65: q65-parm yes
// Q65: can-run-plan no
