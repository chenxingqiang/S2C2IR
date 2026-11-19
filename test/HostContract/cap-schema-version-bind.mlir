// Query bind: CUDA and Ascend capability schema version and fields.
// No semantic cut. v3 stays not-claimed.
// RUN: python3 %S/../../runtime/record_cap_schema_version_bind.py --print-cap-schema-version-bind | FileCheck %s --check-prefix=CSV
// CSV: cap-schema-version-bind gate=query
// CSV: cap-schema-version 1
// CSV: cap-schema-fields 21
// CSV: cap-schema-version-bind yes
// CSV: can-run-plan no
