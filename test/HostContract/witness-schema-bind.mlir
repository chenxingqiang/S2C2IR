// Apply witness schema bind. Query only. No semantic cut.
// can-run-plan stays no. Do not print applied=yes.
// RUN: python3 %S/../../runtime/record_witness_schema_bind.py --print-witness-schema-bind | FileCheck %s --check-prefix=WIT --implicit-check-not=applied=yes --implicit-check-not="can-run-plan yes" --implicit-check-not="semantic-cut yes"
// WIT: witness-schema-bind gate=query
// WIT: witness-schema s2c2.apply_legality_witness.v1
// WIT: apply-schema s2c2.storage_apply.v1
// WIT: witness-schema-bind yes
// WIT: can-run-plan no
