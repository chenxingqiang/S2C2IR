// Evidence, predicate, and decision reason tokens stay out of authorization.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Do not FileCheck microseconds.
// RUN: python3 %S/../../runtime/record_evidence_reason_ns_bind.py --print-evidence-reason-ns-bind | FileCheck %s --check-prefix=ERN --implicit-check-not=authorization=yes
// ERN: evidence-reason-ns-bind gate=query
// ERN: evidence-reason-count 19
// ERN: evidence-reason-ns-bind yes
// ERN: can-run-plan no
