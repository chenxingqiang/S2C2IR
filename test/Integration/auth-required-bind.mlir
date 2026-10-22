// Authorization required inputs and policy id.
// REQUIRED, POLICY_V01, and LICENSE_SUBJECT come from the frozen host.
// This lit test is not in check-host. No semantic cut. can-run-plan stays no.
// Do not add required inputs. Do not print authorization=yes or rewrite-license=yes.
// RUN: python3 %S/../../runtime/record_auth_required_bind.py --print-auth-required-bind | FileCheck %s --check-prefix=ARQ --implicit-check-not=authorization=yes --implicit-check-not=rewrite-license=yes --implicit-check-not=can-run-plan=yes
// ARQ: auth-required-bind gate=query
// ARQ: required-count 4
// ARQ: policy authorization-policy-v0.1
// ARQ: license-subject rewrite-license
// ARQ: auth-required-bind yes
// ARQ: can-run-plan no
