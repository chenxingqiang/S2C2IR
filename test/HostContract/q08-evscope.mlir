// Evidence scope and schema stay candidate-local and s2c2.evidence.v1.
// Query only. No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_q08_evscope.py --print-q08-evscope | FileCheck %s --check-prefix=Q08 --implicit-check-not=can-run-plan=yes
// Q08: q08-evscope gate=query
// Q08: evidence-scope candidate-local
// Q08: evidence-schema s2c2.evidence.v1
// Q08: q08-evscope yes
// Q08: can-run-plan no
