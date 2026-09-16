// Realization Legality v1. Constraint facts only.
// Not sufficient, not can-run-plan, not rewrite.
// Do not FileCheck microseconds. This file does not require s2c2-opt.
// RUN: python3 %S/../../runtime/record_realization_legality.py --print-realization-legality-contract | FileCheck %s --check-prefix=LEG --implicit-check-not='decision-subject sufficient' --implicit-check-not=can-run-plan=yes
// RUN: python3 %S/../../runtime/record_realization_legality.py --print-realization-legality-matrix | FileCheck %s --check-prefix=LEGM --implicit-check-not='subject=sufficient' --implicit-check-not=can-run-plan=yes --implicit-check-not='rewrite-license=yes'

func.func @dummy() {
  return
}

// LEG: realization-legality gate=query
// LEG: schema s2c2.realization_legality.v1
// LEG: source-schema s2c2.capability_profile.v1
// LEG: legality-identity target-device-kind
// LEG: constraint-copied yes
// LEG: legality-ne-applicable yes
// LEG: legality-ne-profile yes
// LEG: legality-ne-sufficient yes
// LEG: unproven-ne-forbidden yes
// LEG: allowed-ne-can-run-plan yes
// LEG: all-allowed-ne-sufficient yes
// LEG: legality-ne-authorization yes
// LEG: legality-ne-rewrite-license yes
// LEG: can-run-plan no
// LEG: sufficiency-evaluation n/a
// LEG: rewrite-license no
// LEG: rewrite-path no
// LEG: capability-schedule-ne-god-object yes
// LEG: generic-schema-validator n/a
// LEG: legality-matrix-cases 8
// LEG: constraint allowed
// LEG: constraint forbidden
// LEG: constraint not-applicable
// LEG: constraint unproven
// LEG: note sufficient-decision-not-emitted
// LEG: note applicable-semantics-frozen

// LEG-NOT: rewrite-license=yes
// LEG-NOT: sufficient=yes
// LEG-NOT: can-run-plan=yes
// LEG-NOT: decision-subject sufficient

// LEGM: realization-legality-matrix gate=query
// LEGM: constraint-copied yes
// LEGM: all-allowed-ne-sufficient yes
// LEGM: unproven-ne-forbidden yes
// LEGM: legality-matrix-cases 8
// LEGM: leg-case allowed-from-yes
// LEGM: leg-fact target=cuda device=sm89:rtx4090 kind=concurrent-pair constraint=allowed reasons=capability.present
// LEGM: leg-sufficiency-evaluation n/a
// LEGM: leg-can-run-plan no
// LEGM: leg-case forbidden-from-no
// LEGM: kind=concurrent-pair constraint=forbidden reasons=capability.not-applicable
// LEGM: leg-case not-applicable-from-na
// LEGM: kind=staged-dma constraint=not-applicable
// LEGM: leg-case unproven-from-missing
// LEGM: kind=concurrent-pair constraint=unproven reasons=capability.missing-evidence
// LEGM: leg-case unproven-from-unknown-provenance
// LEGM: kind=concurrent-pair constraint=unproven
// LEGM: leg-case all-allowed-ne-sufficient
// LEGM: kind=concurrent-pair constraint=allowed
// LEGM: kind=named-nonblocking constraint=allowed
// LEGM: kind=staged-dma constraint=allowed
// LEGM: leg-sufficiency-evaluation n/a
// LEGM: leg-can-run-plan no
// LEGM: leg-case one-kind-forbidden
// LEGM: kind=concurrent-pair constraint=forbidden
// LEGM: kind=named-nonblocking constraint=allowed
// LEGM: kind=staged-dma constraint=allowed
// LEGM: leg-case mixed-allowed-unproven
// LEGM: kind=concurrent-pair constraint=allowed
// LEGM: kind=named-nonblocking constraint=unproven
// LEGM: kind=staged-dma constraint=unproven
// LEGM: rewrite-license no
// LEGM: can-run-plan no
// LEGM-NOT: rewrite-license=yes
// LEGM-NOT: sufficient=yes
// LEGM-NOT: subject=sufficient
// LEGM-NOT: can-run-plan=yes
