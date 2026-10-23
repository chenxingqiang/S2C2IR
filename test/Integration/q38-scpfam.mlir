// Evidence scope-mismatch family and its three displays.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Does not call run_analyzer.
// RUN: python3 %S/../../runtime/record_q38_scpfam.py --print-q38-scpfam | FileCheck %s --check-prefix=Q38 --implicit-check-not=can-run-plan=yes
// Q38: q38-scpfam gate=query
// Q38: scope-family evidence.scope-mismatch
// Q38: scope-display unknown-scope
// Q38: scope-display replica-scope-mismatch
// Q38: scope-display destination-scope-mismatch
// Q38: q38-scpfam yes
// Q38: can-run-plan no
