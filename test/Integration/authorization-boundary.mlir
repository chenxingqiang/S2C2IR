// 7A Authorization Boundary. Host-side Decision contract.
// Not a compiler E2E. Does not require s2c2-opt. Not 7B rewrite.
// sufficient ≠ authorized ≠ rewrite-license.
// Do not FileCheck microseconds.
// RUN: python3 %S/../../runtime/record_authorization.py --print-authorization-contract | FileCheck %s --check-prefix=AUTH --implicit-check-not=can-run-plan=yes --implicit-check-not=rewrite-path=yes --implicit-check-not=decision.authorized-closed --implicit-check-not=decision.rewrite-license-closed --implicit-check-not=decision.identity-mismatch
// RUN: python3 %S/../../runtime/record_authorization.py --print-authorization-matrix | FileCheck %s --check-prefix=AUTHM --implicit-check-not=can-run-plan=yes --implicit-check-not=rewrite-path=yes --implicit-check-not=decision.authorized-closed --implicit-check-not=decision.rewrite-license-closed --implicit-check-not=decision.identity-mismatch

func.func @dummy() {
  return
}

// AUTH: authorization-evaluator gate=query
// AUTH: schema s2c2.authorization.v1
// AUTH: decision-schema s2c2.decision.v1
// AUTH: decision-subject authorized
// AUTH: decision-subject rewrite-license
// AUTH: authorization-identity selected-object-action
// AUTH: license-identity selected-object-action-license-kind
// AUTH: policy authorization-policy-v0.1
// AUTH: action storage-rewrite
// AUTH: license-kind storage-capacity-rewrite
// AUTH: sufficient-ne-authorized yes
// AUTH: authorized-ne-rewrite-license yes
// AUTH: sufficient-yes-ne-authorized yes
// AUTH: authorized-yes-ne-rewrite-license yes
// AUTH: authorized-yes-ne-rewrite-path yes
// AUTH: rewrite-license-yes-ne-transformation yes
// AUTH: inputs-canonical-order yes
// AUTH: duplicate-required-safe-no yes
// AUTH: duplicate-license-safe-no yes
// AUTH: license-input-not-ignored-extra yes
// AUTH: claimed-action-ne-identity-action yes
// AUTH: authorization-namespace v0.1
// AUTH: ea-1-authorization-tokens none
// AUTH: host-side-decision-contract yes
// AUTH: compiler-e2e no
// AUTH: can-run-plan no
// AUTH: rewrite-path no
// AUTH: transformation n/a
// AUTH: capability-schedule-ne-god-object yes
// AUTH: generic-schema-validator n/a
// AUTH: authorization-matrix-cases 20
// AUTH: required-input sufficient
// AUTH: required-input policy-match
// AUTH: required-input provenance
// AUTH: required-input action-match
// AUTH: license-input rewrite-license
// AUTH: token authorization.sufficient-no
// AUTH: token authorization.policy-mismatch
// AUTH: token authorization.policy-unknown
// AUTH: token authorization.provenance-unknown
// AUTH: token authorization.action-mismatch
// AUTH: token authorization.identity-mismatch
// AUTH: token authorization.duplicate-license
// AUTH: token authorization.authorized-no
// AUTH: token authorization.authorized-closed
// AUTH: token authorization.rewrite-license-missing
// AUTH: token authorization.rewrite-license-no
// AUTH: token authorization.rewrite-license-closed
// AUTH-NOT: token decision.authorized-closed
// AUTH-NOT: token decision.rewrite-license-closed
// AUTH: note six-c-m-frozen
// AUTH: note seven-a-opened
// AUTH: note seven-b-rewrite-closed
// AUTH: note ea-1-still-usable-only
// AUTH-NOT: can-run-plan=yes
// AUTH-NOT: rewrite-path=yes

// AUTHM: authorization-matrix gate=query
// AUTHM: decision-subject authorized
// AUTHM: decision-subject rewrite-license
// AUTHM: sufficient-ne-authorized yes
// AUTHM: authorized-ne-rewrite-license yes
// AUTHM: inputs-canonical-order yes
// AUTHM: authorization-matrix-cases 20
// AUTHM: auth-case sufficient-no
// AUTHM: auth-authorized subject=authorized result=no reasons=authorization.sufficient-no
// AUTHM: auth-license subject=rewrite-license result=no reasons=authorization.authorized-no
// AUTHM: auth-case sufficient-yes-policy-missing
// AUTHM: auth-authorized subject=authorized result=no reasons=predicate.missing-input
// AUTHM: auth-case wrong-policy
// AUTHM: auth-authorized subject=authorized result=no reasons=authorization.policy-mismatch
// AUTHM: auth-case unknown-policy
// AUTHM: auth-authorized subject=authorized result=no reasons=authorization.policy-unknown
// AUTHM: auth-case action-mismatch
// AUTHM: auth-authorized subject=authorized result=no reasons=authorization.action-mismatch
// AUTHM: auth-case selected-mismatch
// AUTHM: auth-authorized subject=authorized result=no reasons=authorization.identity-mismatch
// AUTHM: auth-case object-mismatch
// AUTHM: auth-authorized subject=authorized result=no reasons=authorization.identity-mismatch
// AUTHM: auth-case provenance-missing
// AUTHM: auth-authorized subject=authorized result=no reasons=predicate.missing-input
// AUTHM: auth-case provenance-unknown
// AUTHM: auth-authorized subject=authorized result=no reasons=authorization.provenance-unknown
// AUTHM: auth-case duplicate-identity
// AUTHM: auth-authorized subject=authorized result=no reasons=decision.duplicate-identity
// AUTHM: auth-case authorized-yes-license-missing
// AUTHM: auth-authorized subject=authorized result=yes reasons=authorization.authorized-closed
// AUTHM: auth-license subject=rewrite-license result=no reasons=authorization.rewrite-license-missing
// AUTHM: auth-case rewrite-license-no
// AUTHM: auth-license subject=rewrite-license result=no reasons=authorization.rewrite-license-no
// AUTHM: auth-case rewrite-license-yes
// AUTHM: auth-authorized subject=authorized result=yes reasons=authorization.authorized-closed
// AUTHM: auth-license subject=rewrite-license result=yes reasons=authorization.rewrite-license-closed
// AUTHM: auth-rewrite-path no
// AUTHM: auth-transformation n/a
// AUTHM: auth-case rewrite-license-kind-mismatch
// AUTHM: auth-license subject=rewrite-license result=no reasons=authorization.identity-mismatch
// AUTHM: auth-case duplicate-license
// AUTHM: auth-authorized subject=authorized result=yes reasons=authorization.authorized-closed
// AUTHM: auth-license subject=rewrite-license result=no reasons=authorization.duplicate-license
// AUTHM: auth-case missing-action-match
// AUTHM: auth-authorized subject=authorized result=no reasons=predicate.missing-input
// AUTHM: auth-case sufficient-n/a
// AUTHM: auth-authorized subject=authorized result=no reasons=authorization.sufficient-no
// AUTHM: auth-case shuffled-required
// AUTHM: auth-envelope-inputs sufficient,policy-match,provenance,action-match
// AUTHM: auth-authorized subject=authorized result=yes reasons=authorization.authorized-closed
// AUTHM: auth-case consume-6c-m-yes
// AUTHM: auth-authorized subject=authorized result=yes reasons=authorization.authorized-closed
// AUTHM: auth-license subject=rewrite-license result=no reasons=authorization.rewrite-license-missing
// AUTHM: auth-case license-yes-but-not-authorized
// AUTHM: auth-authorized subject=authorized result=no reasons=authorization.sufficient-no
// AUTHM: auth-license subject=rewrite-license result=no reasons=authorization.authorized-no
// AUTHM: can-run-plan no
// AUTHM: rewrite-path no
// AUTHM: transformation n/a
// AUTHM-NOT: can-run-plan=yes
// AUTHM-NOT: rewrite-path=yes
