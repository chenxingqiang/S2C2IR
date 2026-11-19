// RUN: python3 %S/../../runtime/record_q15_ledrole.py --print-q15-ledrole | FileCheck %s --check-prefix=Q15 --implicit-check-not=can-run-plan=yes
// Q15: q15-ledrole gate=query
// Q15: ledger-role catalog-69
// Q15: ledger-role overlay
// Q15: ledger-role compiler-4090
// Q15: ledger-role campaign
// Q15: ledger-role pending-program
// Q15: ledger-role program
// Q15: q15-ledrole yes
// Q15: can-run-plan no
