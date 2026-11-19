// Closed capability targets. Query only. Do not add targets.
// No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_targets_closed_bind.py --print-targets-closed-bind | FileCheck %s --check-prefix=TGT
// TGT: gate=query
// TGT: target cpu
// TGT: target cuda
// TGT: target rocm
// TGT: target sycl
// TGT: target ascend
// TGT: target npu
// TGT: target cim
// TGT: targets-closed-bind yes
// TGT: can-run-plan no
