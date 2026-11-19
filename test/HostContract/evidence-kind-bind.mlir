// Evidence kind, record, and database schemas stay distinct.
// Query only. No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_evidence_kind_bind.py --print-evidence-kind-bind | FileCheck %s --check-prefix=EKB
// EKB: evidence-kind-bind gate=query
// EKB: kind-schema s2c2.evidence_kind.v1
// EKB: record-schema s2c2.evidence_record.v1
// EKB: evidence-schema s2c2.evidence.v1
// EKB: evidence-kind-bind yes
// EKB: can-run-plan no
