// Rewrite reason tokens printed as rewrite-token lines.
// Query only. No semantic cut. can-run-plan stays no.
// Does not call run_analyzer. No device, predicate, dialect, or backend.
// RUN: python3 %S/../../runtime/record_q05_reword.py --print-q05-reword | FileCheck %s --check-prefix=Q05 --implicit-check-not=can-run-plan=yes --implicit-check-not=rewrite-path=yes
// Q05: q05-reword gate=query
// Q05: rewrite-token rewrite.license-no
// Q05: rewrite-token rewrite.identity-mismatch
// Q05: rewrite-token rewrite.sequence-mismatch
// Q05: rewrite-token rewrite.duplicate-envelope
// Q05: rewrite-token rewrite.duplicate-sequence
// Q05: rewrite-token rewrite.plan-closed
// Q05: q05-reword yes
// Q05: can-run-plan no
