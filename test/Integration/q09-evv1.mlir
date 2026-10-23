// Measured storage cost v1 stays distinct from the evidence schema.
// Query only. No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_q09_evv1.py --print-q09-evv1 | FileCheck %s --check-prefix=Q09 --implicit-check-not=can-run-plan=yes
// Q09: q09-evv1 gate=query
// Q09: measured-schema s2c2.measured_storage_cost.v1
// Q09: evidence-schema s2c2.evidence.v1
// Q09: q09-evv1 yes
// Q09: can-run-plan no
