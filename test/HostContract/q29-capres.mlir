// Capacity residency fields from record_capacity.RES_FIELDS.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Does not add a capacity predicate.
// RUN: python3 %S/../../runtime/record_q29_capres.py --print-q29-capres | FileCheck %s --check-prefix=Q29 --implicit-check-not=can-run-plan=yes
// Q29: q29-capres gate=query
// Q29: res-field id
// Q29: res-field object
// Q29: res-field space
// Q29: res-field size
// Q29: res-field live
// Q29: res-field producer
// Q29: res-field consumer
// Q29: res-field reuse_distance
// Q29: q29-capres yes
// Q29: can-run-plan no
