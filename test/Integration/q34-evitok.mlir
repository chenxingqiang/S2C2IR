// Evidence reason tokens. Query only.
// No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Do not FileCheck microseconds.
// RUN: python3 %S/../../runtime/record_q34_evitok.py --print-q34-evitok | FileCheck %s --check-prefix=Q34 --implicit-check-not=can-run-plan=yes --implicit-check-not=authorization=yes
// Q34: q34-evitok gate=query
// Q34: evidence-token evidence.unknown-witness
// Q34: evidence-token evidence.scope-mismatch
// Q34: evidence-token evidence.no-source-replica
// Q34: evidence-token evidence.no-validity-witness
// Q34: evidence-token evidence.no-ordering-witness
// Q34: evidence-token evidence.no-invalidation-witness
// Q34: evidence-token evidence.interval-does-not-cover
// Q34: evidence-token evidence.not-before-consumer
// Q34: evidence-token evidence.witnessed-unmutated-cover
// Q34: evidence-token evidence.witnessed-before-consumer
// Q34: evidence-token evidence.witnessed-drop-stale
// Q34: q34-evitok yes
// Q34: can-run-plan no
