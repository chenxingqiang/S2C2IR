// Ascend adapter schedule header constants. Query only.
// This lit test is not in check-host. No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_q94_ashdr.py --print-q94-ashdr | FileCheck %s --check-prefix=Q94 --implicit-check-not=can-run-plan=yes
// Q94: q94-ashdr gate=query
// Q94: ascend-sched npu-async
// Q94: ascend-map default
// Q94: ascend-device npu
// Q94: ascend-sync named-nonblocking
// Q94: ascend-hardware ascend910b:ascend
// Q94: q94-ashdr yes
// Q94: can-run-plan no
