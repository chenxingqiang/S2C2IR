// Capacity source-data fields. Query only.
// No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_q24_capsdat.py --print-q24-capsdat | FileCheck %s --check-prefix=Q24 --implicit-check-not=can-run-plan=yes
// Q24: q24-capsdat gate=query
// Q24: source-data-field object
// Q24: source-data-field replica
// Q24: source-data-field witness
// Q24: source-data-field live
// Q24: source-data-field scope
// Q24: q24-capsdat yes
// Q24: can-run-plan no
