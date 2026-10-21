// RUN: python3 %S/../../runtime/record_cuda_pilot_bind.py --print-cuda-pilot-header | FileCheck %s --check-prefix=PIL
// PIL: cuda-pilot-header gate=query
// PIL: cuda-pilot-count 3
// PIL: cuda-pilot-header-bound yes
// PIL: can-run-plan no
