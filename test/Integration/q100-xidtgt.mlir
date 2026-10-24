// Cross-identity checking case targets from record_realization_checking_xid.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Do not FileCheck microseconds.
// RUN: python3 %S/../../runtime/record_q100_xidtgt.py --print-q100-xidtgt | FileCheck %s --check-prefix=Q100 --implicit-check-not=can-run-plan=yes
// Q100: q100-xidtgt gate=query
// Q100: xid-target cuda
// Q100: xid-target ascend
// Q100: xid-target cpu
// Q100: xid-target ascend
// Q100: q100-xidtgt yes
// Q100: can-run-plan no
