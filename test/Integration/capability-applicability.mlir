// Capability / Applicability host contract. Query only.
// Decision.subject=applicable. Not sufficient, not rewrite.
// Do not FileCheck microseconds. This file does not require s2c2-opt.
// RUN: python3 %S/../../runtime/record_capability_applicability.py --print-capability-applicability-contract | FileCheck %s --check-prefix=CAPA --implicit-check-not=sufficient-not-composed --implicit-check-not='decision-subject sufficient'
// RUN: python3 %S/../../runtime/record_capability_applicability.py --print-capability-applicability-matrix | FileCheck %s --check-prefix=CAPM --implicit-check-not='capa-decision subject=usable' --implicit-check-not='capa-decision subject=sufficient'

func.func @dummy() {
  return
}

// CAPA: capability-applicability gate=query
// CAPA: schema s2c2.capability_applicability.v1
// CAPA: decision-subject applicable
// CAPA: applicable-ne-usable yes
// CAPA: applicable-ne-sufficient yes
// CAPA: capability-ne-authorization yes
// CAPA: capability-ne-rewrite yes
// CAPA: v3-catalog-ne-applicability-record yes
// CAPA: capability-schedule-ne-god-object yes
// CAPA: identity-cardinality 0-or-1
// CAPA: duplicate-identity safe-no
// CAPA: identity-kind-agrees yes
// CAPA: identity-mismatch safe-no
// CAPA: unknown-provenance missing-evidence
// CAPA: raw-record-revalidated yes
// CAPA: invalid-schema unknown-reason
// CAPA: invalid-canonical unknown-reason
// CAPA: invalid-applicability unknown-reason
// CAPA: invalid-provenance missing-evidence
// CAPA: authorization-canonical-ne-decision-reason yes
// CAPA: sufficiency-evaluation n/a
// CAPA: rewrite-license no
// CAPA: rewrite-path no
// CAPA: target cpu
// CAPA: target cuda
// CAPA: target rocm
// CAPA: target sycl
// CAPA: target ascend
// CAPA: target npu
// CAPA: target cim
// CAPA: kind concurrent-pair
// CAPA: kind named-nonblocking
// CAPA: kind staged-dma
// CAPA: token capability.present
// CAPA: token capability.missing-evidence
// CAPA: token capability.unknown-target
// CAPA: token capability.unknown-kind
// CAPA: note six-c-m-sufficient-parked
// CAPA: note occupancy-usable-ne-applicable
// CAPA: note dest-invalidation-ne-applicable
// CAPA-NOT: rewrite-license=yes
// CAPA-NOT: sufficient=yes
// CAPA-NOT: decision-subject sufficient

// CAPM: capability-applicability-matrix gate=query
// CAPM: derive-subject applicable
// CAPM: derive-scope target-device-kind
// CAPM: unknown-provenance missing-evidence
// CAPM: raw-record-revalidated yes
// CAPM: authorization-canonical-ne-decision-reason yes
// CAPM: capa-case cuda-pair-present
// CAPM: capa-decision subject=applicable result=yes reasons=capability.present
// CAPM: capa-case missing-evidence
// CAPM: capa-decision subject=applicable result=no reasons=capability.missing-evidence
// CAPM: capa-case unknown-provenance
// CAPM: applicability=yes provenance=unknown
// CAPM: capa-decision subject=applicable result=no reasons=capability.missing-evidence
// CAPM: capa-case unknown-target
// CAPM: capa-decision subject=applicable result=no reasons=capability.unknown-target
// CAPM: capa-case unknown-kind
// CAPM: kind=sufficient
// CAPM: capa-decision subject=applicable result=no reasons=capability.unknown-kind
// CAPM: capa-case usable-ne-applicable
// CAPM: occupancy_usable=yes
// CAPM: capa-decision subject=applicable result=no reasons=capability.not-applicable
// CAPM: capa-case dest-inv-ne-applicable
// CAPM: capa-decision subject=applicable result=no reasons=capability.missing-evidence
// CAPM: capa-case ignore-other-device
// CAPM: capa-decision subject=applicable result=no reasons=capability.missing-evidence
// CAPM: capa-case duplicate-identity
// CAPM: capa-decision subject=applicable result=no reasons=decision.duplicate-identity
// CAPM: capa-case identity-kind-mismatch
// CAPM: capa-decision subject=applicable result=no reasons=decision.identity-mismatch
// CAPM: capa-case ascend-dma-present
// CAPM: capa-decision subject=applicable result=yes reasons=capability.present
// CAPM: capa-case cpu-pair-not-applicable
// CAPM: capa-decision subject=applicable result=no reasons=capability.not-applicable
// CAPM: capa-case invalid-schema
// CAPM: schema=s2c2.evidence_record.v1
// CAPM: capa-decision subject=applicable result=no reasons=decision.unknown-reason
// CAPM: capa-case invalid-canonical
// CAPM: canonical=authorization.rewrite
// CAPM: capa-decision subject=applicable result=no reasons=decision.unknown-reason
// CAPM: capa-case invalid-applicability
// CAPM: applicability=maybe
// CAPM: capa-decision subject=applicable result=no reasons=decision.unknown-reason
// CAPM: capa-case invalid-provenance
// CAPM: provenance=invented
// CAPM: capa-decision subject=applicable result=no reasons=capability.missing-evidence
// CAPM: rewrite-license no
// CAPM-NOT: rewrite-license=yes
// CAPM-NOT: sufficient=yes
// CAPM-NOT: capa-decision subject=usable
// CAPM-NOT: capa-decision subject=sufficient
// CAPM-NOT: reasons=authorization.rewrite
