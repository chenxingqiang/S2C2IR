// USABLE_KINDS stays source-data then restore-ordering.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host.
// RUN: python3 %S/../../runtime/record_q31_usekind.py --print-q31-usekind | FileCheck %s --check-prefix=Q31 --implicit-check-not=can-run-plan=yes --implicit-check-not='decision-subject sufficient'
// Q31: q31-usekind gate=query
// Q31: usable-kind source-data
// Q31: usable-kind restore-ordering
// Q31: q31-usekind yes
// Q31: can-run-plan no
