// CUDA VAL_ASYNC_ARMS from runtime/cuda/record_v3.py.
// This lit test is not in check-host. No semantic cut. can-run-plan stays no.
// Do not FileCheck microseconds. This file does not require s2c2-opt.
// RUN: python3 %S/../../runtime/record_q73_vas.py --print-q73-vas | FileCheck %s --check-prefix=Q73 --implicit-check-not=can-run-plan=yes
// Q73: q73-vas gate=query
// Q73: async-arm val-async-copy
// Q73: async-arm val-async-compute
// Q73: async-arm val-async-life-sync
// Q73: async-arm val-async-life-async
// Q73: async-arm val-async-hb
// Q73: q73-vas yes
// Q73: can-run-plan no
