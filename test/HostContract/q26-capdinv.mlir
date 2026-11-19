// Capacity dest-invalidation fields are object, destination, witness, and scope.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host.
// RUN: python3 %S/../../runtime/record_q26_capdinv.py --print-q26-capdinv | FileCheck %s --check-prefix=Q26 --implicit-check-not=can-run-plan=yes
// Q26: q26-capdinv gate=query
// Q26: dest-inv-field object
// Q26: dest-inv-field destination
// Q26: dest-inv-field witness
// Q26: dest-inv-field scope
// Q26: q26-capdinv yes
// Q26: can-run-plan no
