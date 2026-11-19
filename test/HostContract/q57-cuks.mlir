// CUDA KS and PROVS from runtime/cuda/record_v3.py.
// This lit test is not in check-host. No semantic cut. can-run-plan stays no.
// Do not FileCheck microseconds. This file does not require s2c2-opt.
// RUN: python3 %S/../../runtime/record_q57_cuks.py --print-q57-cuks | FileCheck %s --check-prefix=Q57 --implicit-check-not=can-run-plan=yes
// Q57: q57-cuks gate=query
// Q57: cuda-k 1
// Q57: cuda-k 8
// Q57: cuda-prov 0
// Q57: cuda-prov 1
// Q57: q57-cuks yes
// Q57: can-run-plan no
