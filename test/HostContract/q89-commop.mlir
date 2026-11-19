// RUN: python3 %S/../../runtime/record_q89_commop.py --print-q89-commop | FileCheck %s --check-prefix=Q89 --implicit-check-not=can-run-plan=yes
// Q89: q89-commop gate=query
// Q89: comm-op copy
// Q89: comm-op stream
// Q89: comm-op barrier
// Q89: q89-commop yes
// Q89: can-run-plan no
