// Capacity source, order, and dest witnesses required by record_capacity.
// Query only. No semantic cut. can-run-plan stays no.
// No capacity predicate, device, dialect, backend, or semantic cut.
// RUN: python3 %S/../../runtime/record_q27_capwit.py --print-q27-capwit | FileCheck %s --check-prefix=Q27 --implicit-check-not=can-run-plan=yes
// Q27: q27-capwit gate=query
// Q27: source-witness spec-unmutated-cover
// Q27: order-witness spec-before-consumer
// Q27: dest-witness spec-drop-stale
// Q27: q27-capwit yes
// Q27: can-run-plan no
