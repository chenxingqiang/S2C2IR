// Realization Checking v0. Per-kind findings only.
// Not sufficient, not can-run-plan, not rewrite.
// Do not FileCheck microseconds. This file does not require s2c2-opt.
// RUN: python3 %S/../../runtime/record_realization_checking.py --print-realization-checking-contract | FileCheck %s --check-prefix=CHK --implicit-check-not='decision-subject sufficient' --implicit-check-not=can-run-plan=yes
// RUN: python3 %S/../../runtime/record_realization_checking.py --print-realization-checking-matrix | FileCheck %s --check-prefix=CHKM --implicit-check-not='subject=sufficient' --implicit-check-not=can-run-plan=yes --implicit-check-not='rewrite-license=yes'

func.func @dummy() {
  return
}

// CHK: realization-checking gate=query
// CHK: schema s2c2.realization_checking.v1
// CHK: claim-schema s2c2.realization_claim.v1
// CHK: source-schema s2c2.realization_legality.v1
// CHK: checking-identity target-device
// CHK: claimed-kinds-canonical yes
// CHK: missing-claimed-kinds-ne-empty yes
// CHK: fact-schema-required yes
// CHK: identity-kind-required yes
// CHK: legality-facts-canonical-order yes
// CHK: unclaimed-kind-ne-violation yes
// CHK: finding-keeps-constraint yes
// CHK: satisfy-ne-can-run-plan yes
// CHK: violate-ne-rewrite-path yes
// CHK: unproven-ne-forbidden yes
// CHK: unproven-ne-missing yes
// CHK: all-satisfy-ne-sufficient yes
// CHK: no-all-satisfy-field yes
// CHK: contract-error-ne-result yes
// CHK: checking-ne-authorization yes
// CHK: checking-ne-rewrite-license yes
// CHK: can-run-plan no
// CHK: sufficiency-evaluation n/a
// CHK: rewrite-license no
// CHK: rewrite-path no
// CHK: capability-schedule-ne-god-object yes
// CHK: generic-schema-validator n/a
// CHK: checking-matrix-cases 17
// CHK: result satisfy
// CHK: result violate
// CHK: result unproven
// CHK: contract-error identity-mismatch
// CHK: contract-error unknown-kind
// CHK: contract-error malformed-legality
// CHK: contract-error invalid-schema
// CHK: note sufficient-decision-not-emitted
// CHK: note applicable-semantics-frozen

// CHK-NOT: rewrite-license=yes
// CHK-NOT: sufficient=yes
// CHK-NOT: can-run-plan=yes
// CHK-NOT: decision-subject sufficient
// CHK-NOT: all-satisfy=

// CHKM: realization-checking-matrix gate=query
// CHKM: finding-keeps-constraint yes
// CHKM: unclaimed-kind-ne-violation yes
// CHKM: all-satisfy-ne-sufficient yes
// CHKM: checking-matrix-cases 17
// CHKM: chk-case satisfy-from-allowed
// CHKM: chk-status ok
// CHKM: chk-finding kind=concurrent-pair result=satisfy constraint=allowed
// CHKM: chk-case violate-from-forbidden
// CHKM: chk-finding kind=concurrent-pair result=violate constraint=forbidden
// CHKM: chk-case violate-from-na
// CHKM: chk-finding kind=staged-dma result=violate constraint=not-applicable
// CHKM: chk-case unproven-from-constraint
// CHKM: chk-finding kind=concurrent-pair result=unproven constraint=unproven
// CHKM: chk-case mixed-claim
// CHKM: chk-finding kind=concurrent-pair result=satisfy constraint=allowed
// CHKM: chk-finding kind=named-nonblocking result=unproven constraint=unproven
// CHKM: chk-case all-claimed-satisfy
// CHKM: chk-finding kind=concurrent-pair result=satisfy constraint=allowed
// CHKM: chk-finding kind=named-nonblocking result=satisfy constraint=allowed
// CHKM: chk-finding kind=staged-dma result=satisfy constraint=allowed
// CHKM: chk-can-run-plan no
// CHKM: chk-case empty-claim
// CHKM: chk-status ok
// CHKM: chk-findings-count 0
// CHKM: chk-case unclaimed-forbidden
// CHKM: chk-status ok
// CHKM: chk-findings-count 1
// CHKM: chk-finding kind=named-nonblocking result=satisfy constraint=allowed
// CHKM: chk-case claimed-kinds-order
// CHKM: chk-finding kind=concurrent-pair result=satisfy
// CHKM: chk-finding kind=staged-dma result=satisfy
// CHKM: chk-case identity-mismatch
// CHKM: chk-status contract-error
// CHKM: chk-error identity-mismatch
// CHKM: chk-findings-count 0
// CHKM: chk-case unknown-kind
// CHKM: chk-error unknown-kind
// CHKM: chk-findings-count 0
// CHKM: chk-case malformed-L-missing-kind
// CHKM: chk-error malformed-legality
// CHKM: chk-findings-count 0
// CHKM: chk-case invalid-schema
// CHKM: chk-error invalid-schema
// CHKM: chk-findings-count 0
// CHKM: chk-case missing-claimed-kinds
// CHKM: chk-status contract-error
// CHKM: chk-error invalid-schema
// CHKM: chk-findings-count 0
// CHKM: chk-case malformed-L-bad-fact-schema
// CHKM: chk-error malformed-legality
// CHKM: chk-findings-count 0
// CHKM: chk-case malformed-L-missing-identity-kind
// CHKM: chk-error malformed-legality
// CHKM: chk-findings-count 0
// CHKM: chk-case malformed-L-conflicting-kind
// CHKM: chk-error malformed-legality
// CHKM: chk-findings-count 0
// CHKM: rewrite-license no
// CHKM: can-run-plan no
// CHKM-NOT: rewrite-license=yes
// CHKM-NOT: sufficient=yes
// CHKM-NOT: subject=sufficient
// CHKM-NOT: can-run-plan=yes
// CHKM-NOT: all-satisfy=
