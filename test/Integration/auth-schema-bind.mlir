// Compare the authorization schema with the decision schema.
// Schemas come from the authorization constants. This lit test is not in check-host.
// No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_auth_schema_bind.py --print-auth-schema-bind | FileCheck %s --check-prefix=ASB

func.func @dummy() {
  return
}

// ASB: auth-schema-bind gate=query
// ASB: authorization-schema s2c2.authorization.v1
// ASB: decision-schema s2c2.decision.v1
// ASB: auth-schema-bind yes
// ASB: can-run-plan no
