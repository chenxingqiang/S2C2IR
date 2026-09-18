// Independent occupancy usable + capability applicable report.
// Two Decisions. Not sufficient, not a conjunction, not rewrite.
// Do not FileCheck microseconds. This file does not require s2c2-opt.
// RUN: python3 %S/../../runtime/record_occupancy_capability.py --print-occupancy-capability-report-contract | FileCheck %s --check-prefix=OCRC --implicit-check-not='decision-subject sufficient' --implicit-check-not=sufficient-not-composed
// RUN: python3 %S/../../runtime/record_occupancy_capability.py --print-occupancy-capability-report-matrix | FileCheck %s --check-prefix=OCRM --implicit-check-not='subject=sufficient' --implicit-check-not='ocr-usable subject=applicable' --implicit-check-not='ocr-applicable subject=usable'

func.func @dummy() {
  return
}

// OCRC: occupancy-capability-report gate=query
// OCRC: schema s2c2.occupancy_capability_report.v1
// OCRC: report-ne-decision yes
// OCRC: usable-identity-ne-applicable-identity yes
// OCRC: conjunction-ne-sufficient yes
// OCRC: both-yes-ne-sufficient yes
// OCRC: decision-subject usable
// OCRC: decision-subject applicable
// OCRC: sufficiency-evaluation n/a
// OCRC: rewrite-license no
// OCRC: rewrite-path no
// OCRC: occupancy-usable-field-ne-usable-decision yes
// OCRC: dest-invalidation-ne-sufficient yes
// OCRC: both-no cartesian
// OCRC: ignore-other-selected yes
// OCRC: ignore-other-object yes
// OCRC: ignore-other-device yes
// OCRC: duplicate-identity safe-no
// OCRC: identity-schema-mismatch no-cross-talk
// OCRC: report-matrix-cases 11
// OCRC: applicable-ne-usable yes
// OCRC: applicable-ne-sufficient yes
// OCRC: usable-ne-sufficient yes
// OCRC: capability-schedule-ne-god-object yes
// OCRC: generic-schema-validator n/a
// OCRC: note six-c-m-sufficient-parked
// OCRC: note sufficient-decision-not-emitted
// OCRC-NOT: rewrite-license=yes
// OCRC-NOT: sufficient=yes
// OCRC-NOT: decision-subject sufficient

// OCRM: occupancy-capability-report-matrix gate=query
// OCRM: report-ne-decision yes
// OCRM: conjunction-ne-sufficient yes
// OCRM: both-yes-ne-sufficient yes
// OCRM: usable-identity-ne-applicable-identity yes
// OCRM: occupancy-usable-field-ne-usable-decision yes
// OCRM: report-matrix-cases 11
// OCRM: ocr-case both-yes-ne-sufficient
// OCRM: ocr-usable subject=usable result=yes
// OCRM: ocr-applicable subject=applicable result=yes reasons=capability.present
// OCRM: ocr-sufficiency-evaluation n/a
// OCRM: ocr-rewrite-license no
// OCRM: ocr-case usable-yes-applicable-no
// OCRM: ocr-usable subject=usable result=yes
// OCRM: ocr-applicable subject=applicable result=no reasons=capability.not-applicable
// OCRM: ocr-sufficiency-evaluation n/a
// OCRM: ocr-case usable-no-applicable-yes
// OCRM: ocr-usable subject=usable result=no reasons=predicate.missing-input
// OCRM: ocr-applicable subject=applicable result=yes reasons=capability.present
// OCRM: ocr-sufficiency-evaluation n/a
// OCRM: ocr-case both-no
// OCRM: ocr-usable subject=usable result=no reasons=predicate.missing-input
// OCRM: ocr-applicable subject=applicable result=no reasons=capability.not-applicable
// OCRM: ocr-sufficiency-evaluation n/a
// OCRM: ocr-case dest-inv-ne-sufficient
// OCRM: kind=dest-invalidation payload-kind=dest-invalidation
// OCRM: ocr-usable subject=usable result=yes
// OCRM: ocr-applicable subject=applicable result=yes reasons=capability.present
// OCRM: ocr-sufficiency-evaluation n/a
// OCRM: ocr-case occupancy-field-ne-usable-decision
// OCRM: occupancy_usable=no
// OCRM: ocr-usable subject=usable result=yes
// OCRM: ocr-applicable subject=applicable result=yes reasons=capability.present
// OCRM: ocr-case ignore-other-selected
// OCRM: ocr-occ-record selected=keep{1,2}|evict{0}|rematerialize{}
// OCRM: ocr-usable subject=usable result=no reasons=predicate.missing-input
// OCRM: ocr-applicable subject=applicable result=yes reasons=capability.present
// OCRM: ocr-case ignore-other-object
// OCRM: object=3 kind=source-data
// OCRM: ocr-usable subject=usable result=no reasons=predicate.missing-input
// OCRM: ocr-applicable subject=applicable result=yes reasons=capability.present
// OCRM: ocr-case ignore-other-device
// OCRM: device=sm80:a100
// OCRM: ocr-usable subject=usable result=yes
// OCRM: ocr-applicable subject=applicable result=no reasons=capability.missing-evidence
// OCRM: ocr-case duplicate-identity
// OCRM: ocr-usable subject=usable result=no reasons=decision.duplicate-identity
// OCRM: ocr-applicable subject=applicable result=no reasons=decision.duplicate-identity
// OCRM: ocr-case identity-schema-mismatch
// OCRM: kind=restore-ordering payload-kind=source-data
// OCRM: schema=s2c2.evidence_record.v1
// OCRM: ocr-usable subject=usable result=no reasons=decision.identity-mismatch
// OCRM: ocr-applicable subject=applicable result=no reasons=decision.unknown-reason
// OCRM: ocr-rewrite-license no
// OCRM: rewrite-license no
// OCRM-NOT: rewrite-license=yes
// OCRM-NOT: sufficient=yes
// OCRM-NOT: subject=sufficient
// OCRM-NOT: ocr-usable subject=applicable
// OCRM-NOT: ocr-applicable subject=usable
