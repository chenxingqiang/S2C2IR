// RUN: python3 %S/../../runtime/record_ascend_workload_header.py --print-ascend-workload-header | FileCheck %s --check-prefix=AWH
// AWH: ascend-workload-header gate=query
// AWH: ascend-workload-count 3
// AWH: ascend-workload-header-bound yes
// AWH: can-run-plan no
