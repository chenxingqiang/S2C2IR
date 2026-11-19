// Predicate reason tokens printed as predicate-token lines.
// Query only. No semantic cut. can-run-plan stays no.
// Does not add a predicate, device, dialect, backend, or semantic cut.
// RUN: python3 %S/../../runtime/record_q35_predtok.py --print-q35-predtok | FileCheck %s --check-prefix=Q35 --implicit-check-not=can-run-plan=yes
// Q35: q35-predtok gate=query
// Q35: predicate-token predicate.missing-input
// Q35: predicate-token predicate.source-data-present
// Q35: predicate-token predicate.restore-ordering-present
// Q35: q35-predtok yes
// Q35: can-run-plan no
