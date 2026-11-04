// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host.
// RUN: python3 %S/../../runtime/record_q96_aslck.py --print-q96-aslck | FileCheck %s --check-prefix=Q96 --implicit-check-not=can-run-plan=yes
// Q96: q96-aslck gate=query
// Q96: header-slack 1.05
// Q96: python-slack 1.05
// Q96: q96-aslck yes
// Q96: can-run-plan no
