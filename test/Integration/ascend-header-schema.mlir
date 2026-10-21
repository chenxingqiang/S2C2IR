// RUN: python3 %S/../../runtime/record_ascend_header_schema.py --print-ascend-header-schema | FileCheck %s --check-prefix=HDR
// HDR: ascend-header-schema gate=query
// HDR: ascend-header-fields 21
// HDR: ascend-header-pairs 3
// HDR: ascend-header-schema-bound yes
// HDR: can-run-plan no
