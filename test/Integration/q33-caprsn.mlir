// Capability reason tokens from record_capability_applicability.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Does not add a predicate.
// RUN: python3 %S/../../runtime/record_q33_caprsn.py --print-q33-caprsn | FileCheck %s --check-prefix=Q33 --implicit-check-not=can-run-plan=yes
// Q33: q33-caprsn gate=query
// Q33: capability-token capability.present
// Q33: capability-token capability.missing-evidence
// Q33: capability-token capability.not-applicable
// Q33: capability-token capability.unknown-target
// Q33: capability-token capability.unknown-kind
// Q33: q33-caprsn yes
// Q33: can-run-plan no
