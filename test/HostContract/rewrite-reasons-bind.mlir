// REWRITE_REASON_TOKENS stay in the rewrite. namespace.
// Query only. No semantic cut. can-run-plan stays no.
// Do not print rewrite-path=yes or applied=yes.
// RUN: python3 %S/../../runtime/record_rewrite_reasons_bind.py --print-rewrite-reasons-bind | FileCheck %s --check-prefix=RRT --implicit-check-not=can-run-plan=yes --implicit-check-not=rewrite-path=yes --implicit-check-not=applied=yes
// RRT: rewrite-reasons-bind gate=query
// RRT: rewrite-reason-count 6
// RRT: rewrite-reasons-bind yes
// RRT: can-run-plan no
