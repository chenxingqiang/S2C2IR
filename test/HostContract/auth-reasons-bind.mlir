// Authorization reason tokens stay in the authorization namespace.
// Query only. No semantic cut. can-run-plan stays no. Do not add tokens.
// RUN: python3 %S/../../runtime/record_auth_reasons_bind.py --print-auth-reasons-bind | FileCheck %s --check-prefix=ARN --implicit-check-not=authorization=yes --implicit-check-not=can-run-plan=yes
// ARN: auth-reasons-bind gate=query
// ARN: auth-reason-count 12
// ARN: auth-reasons-bind yes
// ARN: can-run-plan no
