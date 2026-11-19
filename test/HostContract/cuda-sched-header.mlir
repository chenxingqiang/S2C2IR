// RUN: python3 %S/../../runtime/record_cuda_sched_header.py --print-cuda-sched-header | FileCheck %s --check-prefix=CSH
// CSH: cuda-sched-header gate=query
// CSH: cuda-sched gpu-async
// CSH: cuda-map default
// CSH: cuda-device gpu
// CSH: cuda-pilot-count 3
// CSH: cuda-sched-header-bound yes
// CSH: can-run-plan no
