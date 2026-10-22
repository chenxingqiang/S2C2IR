// RUN: python3 %S/../../runtime/record_report_foreign_schema.py --print-report-foreign-schemas | FileCheck %s --check-prefix=RFS
// RFS: report-foreign-schemas gate=query
// RFS: report-schema s2c2.occupancy_capability_report.v1
// RFS: sufficiency-schema s2c2.sufficiency.v1
// RFS: checking-schema s2c2.realization_checking.v1
// RFS: report-foreign-schemas-distinct yes
// RFS: can-run-plan no
