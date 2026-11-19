// RUN: python3 %S/../../runtime/record_applicability_values_bind.py --print-applicability-values-bind | FileCheck %s --check-prefix=APV
// APV: applicability-values-bind gate=query
// APV: applicability yes,no,n/a
// APV: provenance catalog,occupancy-query,unknown
// APV: occupancy-usable yes,no,n/a
// APV: applicability-values-bind yes
// APV: can-run-plan no
