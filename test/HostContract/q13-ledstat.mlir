// LEDGER_STATUS from record_hw_ledger, in order.
// Query only. No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_q13_ledstat.py --print-q13-ledstat | FileCheck %s --check-prefix=Q13 --implicit-check-not=can-run-plan=yes
// Q13: q13-ledstat gate=query
// Q13: ledger-status measured
// Q13: ledger-status device-absent
// Q13: q13-ledstat yes
// Q13: can-run-plan no
