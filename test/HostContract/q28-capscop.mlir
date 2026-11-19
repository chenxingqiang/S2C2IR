// Capacity scopes required by record_capacity SOURCE_SCOPE, ORDER_SCOPE, and DEST_SCOPE.
// Query only. No semantic cut. can-run-plan stays no.
// No capacity predicate, device, dialect, backend, or semantic cut.
// RUN: python3 %S/../../runtime/record_q28_capscop.py --print-q28-capscop | FileCheck %s --check-prefix=Q28 --implicit-check-not=can-run-plan=yes
// Q28: q28-capscop gate=query
// Q28: source-scope occupancy-live
// Q28: order-scope occupancy-live
// Q28: dest-scope occupancy-live
// Q28: q28-capscop yes
// Q28: can-run-plan no
