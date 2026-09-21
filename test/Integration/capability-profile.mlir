// Capability Profile / Applicability aggregation. Query only.
// Profile ≠ applicable ≠ usable ≠ sufficient. Not a rewrite.
// Do not FileCheck microseconds. This file does not require s2c2-opt.
// RUN: python3 %S/../../runtime/record_capability_profile.py --print-capability-profile-contract | FileCheck %s --check-prefix=PROF --implicit-check-not='decision-subject sufficient' --implicit-check-not=can-run-plan=yes
// RUN: python3 %S/../../runtime/record_capability_profile.py --print-capability-profile-matrix | FileCheck %s --check-prefix=PROFM --implicit-check-not='subject=sufficient' --implicit-check-not=can-run-plan=yes --implicit-check-not='rewrite-license=yes'

func.func @dummy() {
  return
}

// PROF: capability-profile gate=query
// PROF: schema s2c2.capability_profile.v1
// PROF: profile-identity target-device
// PROF: profile-ne-applicable yes
// PROF: profile-ne-usable yes
// PROF: profile-ne-sufficient yes
// PROF: profile-ne-decision yes
// PROF: absence-ne-no yes
// PROF: missing-evidence-ne-forbidden yes
// PROF: one-kind-no-ne-profile-collapse yes
// PROF: all-yes-ne-sufficient yes
// PROF: usable-ne-capability yes
// PROF: can-run-plan no
// PROF: sufficiency-evaluation n/a
// PROF: rewrite-license no
// PROF: rewrite-path no
// PROF: capability-schedule-ne-god-object yes
// PROF: generic-schema-validator n/a
// PROF: profile-matrix-cases 10
// PROF: kind concurrent-pair
// PROF: kind named-nonblocking
// PROF: kind staged-dma
// PROF: constraint allowed
// PROF: constraint forbidden
// PROF: constraint not-applicable
// PROF: constraint unproven
// PROF: note six-c-m-sufficient-parked
// PROF: note sufficient-decision-not-emitted
// PROF: note kinds-closed
// PROF-NOT: rewrite-license=yes
// PROF-NOT: sufficient=yes
// PROF-NOT: can-run-plan=yes
// PROF-NOT: decision-subject sufficient

// PROFM: capability-profile-matrix gate=query
// PROFM: profile-ne-sufficient yes
// PROFM: absence-ne-no yes
// PROFM: all-yes-ne-sufficient yes
// PROFM: profile-matrix-cases 10
// PROFM: prof-case profile-aggregation
// PROFM: prof-cap kind=concurrent-pair subject=applicable result=yes reasons=capability.present provenance=catalog constraint=allowed
// PROFM: prof-cap kind=named-nonblocking subject=applicable result=no reasons=capability.not-applicable provenance=catalog constraint=forbidden
// PROFM: prof-cap kind=staged-dma subject=applicable result=yes reasons=capability.present provenance=catalog constraint=allowed
// PROFM: prof-sufficiency-evaluation n/a
// PROFM: prof-case unknown-capability
// PROFM: prof-cap kind=concurrent-pair subject=applicable result=no reasons=capability.missing-evidence provenance=missing constraint=unproven
// PROFM: prof-cap kind=named-nonblocking subject=applicable result=no reasons=capability.missing-evidence provenance=missing constraint=unproven
// PROFM: prof-case one-kind-no
// PROFM: constraint=forbidden
// PROFM: prof-cap kind=named-nonblocking subject=applicable result=yes reasons=capability.present provenance=catalog constraint=allowed
// PROFM: prof-case ignore-other-device
// PROFM: device=sm80:a100
// PROFM: provenance=missing constraint=unproven
// PROFM: prof-case duplicate-identity
// PROFM: reasons=decision.duplicate-identity provenance=unknown constraint=unproven
// PROFM: prof-cap kind=named-nonblocking subject=applicable result=yes reasons=capability.present provenance=catalog constraint=allowed
// PROFM: prof-case unknown-provenance
// PROFM: provenance=unknown constraint=unproven
// PROFM: prof-cap kind=named-nonblocking subject=applicable result=yes reasons=capability.present provenance=catalog constraint=allowed
// PROFM: prof-case usable-ne-capability
// PROFM: reasons=capability.missing-evidence provenance=missing constraint=unproven
// PROFM: prof-case all-yes-ne-sufficient
// PROFM: constraint=allowed
// PROFM: prof-sufficiency-evaluation n/a
// PROFM: prof-case no-authorization
// PROFM: result=n/a reasons=none provenance=catalog constraint=not-applicable
// PROFM: prof-case no-rewrite-path
// PROFM: prof-rewrite-path no
// PROFM: rewrite-path no
// PROFM: can-run-plan no
// PROFM-NOT: rewrite-license=yes
// PROFM-NOT: sufficient=yes
// PROFM-NOT: subject=sufficient
// PROFM-NOT: can-run-plan=yes
