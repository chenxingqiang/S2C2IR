// Nine capacity schema constants. Query only.
// No semantic cut. can-run-plan stays no.
// Do not FileCheck microseconds.
// RUN: python3 %S/../../runtime/record_capacity_schema_bind.py --print-cap-nine-schemas | FileCheck %s --check-prefix=C9
// C9: cap-nine-schemas gate=query
// C9: cap-nine-count 9
// C9: cap-nine-schemas-distinct yes
// C9: can-run-plan no
