// 6C-M Sufficiency Decision. Host-side Decision contract.
// Not a compiler E2E. Does not require s2c2-opt.
// Decision.subject=sufficient is an evaluator, not usable∧applicable.
// Scope is (selected, object). sufficient ≠ authorized ≠ rewrite-license.
// Do not FileCheck microseconds.
// RUN: python3 %S/../../runtime/record_sufficiency.py --print-sufficiency-contract | FileCheck %s --check-prefix=SUF --implicit-check-not=can-run-plan=yes --implicit-check-not=rewrite-license=yes --implicit-check-not=authorization=yes
// RUN: python3 %S/../../runtime/record_sufficiency.py --print-sufficiency-matrix | FileCheck %s --check-prefix=SUFM --implicit-check-not=can-run-plan=yes --implicit-check-not=rewrite-license=yes --implicit-check-not=authorization=yes

func.func @dummy() {
  return
}

// SUF: sufficiency-evaluator gate=query
// SUF: schema s2c2.sufficiency.v1
// SUF: decision-schema s2c2.decision.v1
// SUF: decision-subject sufficient
// SUF: decision-has-subject yes
// SUF: evaluator-scope selected-object
// SUF: required-identity-eq-scope yes
// SUF: evaluator-ne-printer-and yes
// SUF: usable-ne-sufficient yes
// SUF: applicable-ne-sufficient yes
// SUF: usable-and-applicable-ne-sufficient yes
// SUF: dest-invalidation-ne-sufficient yes
// SUF: cross-scope-identity-mismatch yes
// SUF: duplicate-required-safe-no yes
// SUF: ignored-extra-duplicate-ne-result yes
// SUF: inputs-canonical-order yes
// SUF: sufficient-ne-authorized yes
// SUF: sufficient-ne-rewrite-license yes
// SUF: sufficient-yes-ne-rewrite-license yes
// SUF: sufficient-ne-can-run-plan yes
// SUF: six-c-i-predicate-ne-six-c-m yes
// SUF: ea-1-still-usable-only yes
// SUF: host-side-decision-contract yes
// SUF: compiler-e2e no
// SUF: sufficiency-evaluation evaluated
// SUF: can-run-plan no
// SUF: authorization n/a
// SUF: rewrite-license no
// SUF: rewrite-path no
// SUF: capability-schedule-ne-god-object yes
// SUF: generic-schema-validator n/a
// SUF: sufficiency-matrix-cases 16
// SUF: required-predicate usable
// SUF: required-predicate restore-ordering
// SUF: required-predicate dest-invalidation
// SUF: required-predicate capacity-legal
// SUF: ignored-extra applicable
// SUF: ignored-extra authorized
// SUF: acceptance a4-same-selected-object-scope
// SUF: acceptance a5-duplicate-required-safe-no
// SUF: acceptance a6-ignored-extras-do-not-affect
// SUF: acceptance a9-canonical-inputs-order
// SUF: acceptance a10-yes-does-not-authorize
// SUF: note six-c-m-opened
// SUF: note seven-a-authorization-closed
// SUF: note rewrite-closed
// SUF: note ea-1-still-usable-only
// SUF-NOT: rewrite-license=yes
// SUF-NOT: can-run-plan=yes
// SUF-NOT: authorization=yes

// SUFM: sufficiency-matrix gate=query
// SUFM: decision-subject sufficient
// SUFM: evaluator-scope selected-object
// SUFM: usable-and-applicable-ne-sufficient yes
// SUFM: dest-invalidation-ne-sufficient yes
// SUFM: cross-scope-identity-mismatch yes
// SUFM: ignored-extra-duplicate-ne-result yes
// SUFM: inputs-canonical-order yes
// SUFM: sufficient-ne-authorized yes
// SUFM: sufficiency-matrix-cases 16
// SUFM: suf-case all-required-yes
// SUFM: suf-envelope-inputs usable,restore-ordering,dest-invalidation,capacity-legal
// SUFM: suf-input subject=usable result=yes
// SUFM: suf-input subject=restore-ordering result=yes
// SUFM: suf-input subject=dest-invalidation result=yes
// SUFM: suf-input subject=capacity-legal result=yes
// SUFM: suf-decision subject=sufficient result=yes reasons=decision.sufficient-closed
// SUFM: suf-sufficiency-evaluation evaluated
// SUFM: suf-can-run-plan no
// SUFM: suf-authorization n/a
// SUFM: suf-rewrite-license no
// SUFM: suf-case dest-inv-historic
// SUFM: suf-input subject=capacity-legal result=absent
// SUFM: suf-decision subject=sufficient result=no reasons=predicate.missing-input
// SUFM: suf-case usable-and-applicable-ne-sufficient
// SUFM: suf-extra subject=applicable result=yes
// SUFM: suf-decision subject=sufficient result=no reasons=predicate.missing-input
// SUFM: suf-case usable-no
// SUFM: suf-decision subject=sufficient result=no reasons=predicate.usable-no
// SUFM: suf-case restore-ordering-no
// SUFM: suf-decision subject=sufficient result=no reasons=predicate.restore-ordering-no
// SUFM: suf-case dest-invalidation-no
// SUFM: suf-decision subject=sufficient result=no reasons=predicate.dest-invalidation-no
// SUFM: suf-case capacity-legal-no
// SUFM: suf-decision subject=sufficient result=no reasons=predicate.capacity-legal-no
// SUFM: suf-case dest-invalidation-n/a
// SUFM: suf-decision subject=sufficient result=no reasons=predicate.dest-invalidation-n/a
// SUFM: suf-case missing-usable
// SUFM: suf-input subject=usable result=absent
// SUFM: suf-decision subject=sufficient result=no reasons=predicate.missing-input
// SUFM: suf-case ignore-applicable-extra
// SUFM: suf-extra subject=applicable result=no
// SUFM: suf-decision subject=sufficient result=yes reasons=decision.sufficient-closed
// SUFM: suf-case duplicate-usable
// SUFM: suf-decision subject=sufficient result=no reasons=decision.duplicate-identity
// SUFM: suf-case ignore-authorized-extra
// SUFM: suf-extra subject=authorized result=yes
// SUFM: suf-decision subject=sufficient result=yes reasons=decision.sufficient-closed
// SUFM: suf-case ignore-duplicate-applicable-extra
// SUFM: suf-extra subject=applicable result=yes
// SUFM: suf-decision subject=sufficient result=yes reasons=decision.sufficient-closed
// SUFM: suf-case ignore-duplicate-authorized-extra
// SUFM: suf-extra subject=authorized result=yes
// SUFM: suf-decision subject=sufficient result=yes reasons=decision.sufficient-closed
// SUFM: suf-case cross-scope
// SUFM: suf-decision subject=sufficient result=no reasons=decision.identity-mismatch
// SUFM: suf-case unknown-capacity-legal
// SUFM: suf-decision subject=sufficient result=no reasons=decision.unknown-reason
// SUFM: suf-authorization n/a
// SUFM: rewrite-license no
// SUFM: can-run-plan no
// SUFM: authorization n/a
// SUFM-NOT: rewrite-license=yes
// SUFM-NOT: can-run-plan=yes
// SUFM-NOT: authorization=yes
