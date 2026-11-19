// LEDGER_KIND from record_hw_ledger, in order.
// Query only. No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_q12_ledkind.py --print-q12-ledkind | FileCheck %s --check-prefix=Q12 --implicit-check-not=can-run-plan=yes
// Q12: q12-ledkind gate=query
// Q12: ledger-kind catalog
// Q12: ledger-kind overlay
// Q12: ledger-kind campaign
// Q12: ledger-kind program
// Q12: q12-ledkind yes
// Q12: can-run-plan no
