// Shared query value set yes,no,n/a. Query only.
// No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Do not FileCheck microseconds.
// RUN: python3 %S/../../runtime/record_q97_ynset.py --print-q97-ynset | FileCheck %s --check-prefix=Q97 --implicit-check-not=can-run-plan=yes --implicit-check-not='decision-subject sufficient'
// Q97: q97-ynset gate=query
// Q97: value-set yes,no,n/a
// Q97: q97-ynset yes
// Q97: can-run-plan no
