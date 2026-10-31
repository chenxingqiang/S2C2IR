// Decision reason tokens. Query only.
// No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Do not FileCheck microseconds.
// RUN: python3 %S/../../runtime/record_q36_dectok.py --print-q36-dectok | FileCheck %s --check-prefix=Q36 --implicit-check-not=can-run-plan=yes --implicit-check-not='decision-subject sufficient'
// Q36: q36-dectok gate=query
// Q36: decision-token decision.subject-required
// Q36: decision-token decision.unknown-subject
// Q36: decision-token decision.unknown-reason
// Q36: decision-token decision.duplicate-identity
// Q36: decision-token decision.identity-mismatch
// Q36: q36-dectok yes
// Q36: can-run-plan no
