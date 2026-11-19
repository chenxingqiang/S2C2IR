// RUN: python3 %S/../../runtime/record_q14_ledtool.py --print-q14-ledtool | FileCheck %s --check-prefix=Q14 --implicit-check-not=can-run-plan=yes
// Q14: q14-ledtool gate=query
// Q14: ledger-tool cuda
// Q14: ledger-tool ascend
// Q14: ledger-tool none
// Q14: q14-ledtool yes
// Q14: can-run-plan no
