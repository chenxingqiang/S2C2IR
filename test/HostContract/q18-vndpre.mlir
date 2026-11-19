// Ledger vendor-key prefixes. Query only. No semantic cut.
// can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_q18_vndpre.py --print-q18-vndpre | FileCheck %s --check-prefix=Q18 --implicit-check-not=can-run-plan=yes
// Q18: q18-vndpre gate=query
// Q18: vendor-prefix acl_
// Q18: vendor-prefix davinci_
// Q18: vendor-prefix cube_
// Q18: vendor-prefix vectorcore_
// Q18: q18-vndpre yes
// Q18: can-run-plan no
