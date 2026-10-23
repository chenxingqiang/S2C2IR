// Capacity optional spec fields stay the four restore and invalidation names.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host.
// RUN: python3 %S/../../runtime/record_q22_capopt.py --print-q22-capopt | FileCheck %s --check-prefix=Q22 --implicit-check-not=can-run-plan=yes
// Q22: q22-capopt gate=query
// Q22: optional-field restore_sources
// Q22: optional-field source_data
// Q22: optional-field restore_order
// Q22: optional-field dest_invalidation
// Q22: q22-capopt yes
// Q22: can-run-plan no
