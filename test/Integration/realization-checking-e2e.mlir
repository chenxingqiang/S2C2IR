// Baseline E2E Integration v0. Compose frozen hosts only.
// Not sufficient, not can-run-plan, not rewrite.
// Do not FileCheck microseconds. This file does not require s2c2-opt.
// RUN: python3 %S/../../runtime/record_realization_checking_e2e.py --print-realization-checking-e2e-contract | FileCheck %s --check-prefix=E2E --implicit-check-not='decision-subject sufficient' --implicit-check-not=can-run-plan=yes
// RUN: python3 %S/../../runtime/record_realization_checking_e2e.py --print-realization-checking-e2e-matrix | FileCheck %s --check-prefix=E2EM --implicit-check-not='subject=sufficient' --implicit-check-not=can-run-plan=yes --implicit-check-not='rewrite-license=yes'

func.func @dummy() {
  return
}

// E2E: realization-checking-e2e gate=query
// E2E: e2e-type integration-reproducibility
// E2E: semantic-expansion none
// E2E: e2e-chain evidence-profile-legality-claim-checking
// E2E: e2e-uses-frozen-hosts yes
// E2E: e2e-reimplements-mapping no
// E2E: e2e-eq-check-v0 yes
// E2E: unclaimed-kind-ne-violation yes
// E2E: contract-error-ne-result yes
// E2E: can-run-plan no
// E2E: sufficiency-evaluation n/a
// E2E: rewrite-license no
// E2E: rewrite-path no
// E2E: capability-schedule-ne-god-object yes
// E2E: e2e-matrix-cases 3
// E2E: note sufficient-decision-not-emitted

// E2E-NOT: rewrite-license=yes
// E2E-NOT: sufficient=yes
// E2E-NOT: can-run-plan=yes
// E2E-NOT: decision-subject sufficient

// E2EM: realization-checking-e2e-matrix gate=query
// E2EM: e2e-eq-check-v0 yes
// E2EM: unclaimed-kind-ne-violation yes
// E2EM: e2e-matrix-cases 3
// E2EM: e2e-case legal-claim
// E2EM: e2e-status ok
// E2EM: e2e-claim-identity target=cuda device=sm89:rtx4090
// E2EM: e2e-finding kind=concurrent-pair result=satisfy constraint=allowed
// E2EM: e2e-finding kind=staged-dma result=unproven constraint=unproven
// E2EM: e2e-can-run-plan no
// E2EM: e2e-case unsatisfied-claim
// E2EM: e2e-status ok
// E2EM: e2e-finding kind=concurrent-pair result=violate constraint=forbidden
// E2EM: e2e-finding kind=staged-dma result=satisfy constraint=allowed
// E2EM: e2e-case identity-mismatch
// E2EM: e2e-status contract-error
// E2EM: e2e-claim-identity target=cuda device=sm80:a100
// E2EM: e2e-error identity-mismatch
// E2EM: e2e-findings-count 0
// E2EM: rewrite-license no
// E2EM: can-run-plan no
// E2EM-NOT: rewrite-license=yes
// E2EM-NOT: sufficient=yes
// E2EM-NOT: subject=sufficient
// E2EM-NOT: can-run-plan=yes
// E2EM-NOT: kind=named-nonblocking
