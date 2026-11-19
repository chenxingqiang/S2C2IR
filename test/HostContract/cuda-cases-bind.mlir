// RUN: python3 %S/../../runtime/record_cuda_cases_bind.py --print-cuda-cases-bind | FileCheck %s --check-prefix=CCB
// CCB: cuda-cases-bind gate=query
// CCB: cuda-case-count 3
// CCB: cuda-cases-bind yes
// CCB: can-run-plan no
