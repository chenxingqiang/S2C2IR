// Decision schema shared by sufficiency, authorization, and storage rewrite.
// Query only. This lit test is not in check-host. No semantic cut.
// can-run-plan stays no. Does not call run_analyzer.
// RUN: python3 %S/../../runtime/record_q98_decschema.py --print-q98-decschema | FileCheck %s --check-prefix=Q98 --implicit-check-not=can-run-plan=yes
// Q98: q98-decschema gate=query
// Q98: decision-schema s2c2.decision.v1
// Q98: q98-decschema yes
// Q98: can-run-plan no
