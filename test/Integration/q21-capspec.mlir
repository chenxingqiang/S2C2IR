// Capacity spec fields. Query only. No semantic cut.
// can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_q21_capspec.py --print-q21-capspec | FileCheck %s --check-prefix=Q21 --implicit-check-not=can-run-plan=yes
// Q21: q21-capspec gate=query
// Q21: spec-field schema
// Q21: spec-field workload_class
// Q21: spec-field space
// Q21: spec-field capacity_tiles
// Q21: spec-field residencies
// Q21: spec-field note
// Q21: q21-capspec yes
// Q21: can-run-plan no
