// Occupancy report schema stays distinct from capability applicability.
// Query only. No semantic cut. can-run-plan stays no.
// Do not print decision-subject sufficient.
// RUN: python3 %S/../../runtime/record_report_capa_bind.py --print-report-capa-bind | FileCheck %s --check-prefix=RCA --implicit-check-not='decision-subject sufficient'
// RCA: report-capa-bind gate=query
// RCA: report-schema s2c2.occupancy_capability_report.v1
// RCA: applicability-schema s2c2.capability_applicability.v1
// RCA: report-capa-bind yes
// RCA: can-run-plan no
