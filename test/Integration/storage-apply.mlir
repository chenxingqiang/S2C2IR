// W0-3/2 Apply Inhabitant v0. One pattern. Not Enum_F.
// Not can-run-plan. Do not FileCheck microseconds.
// RUN: python3 %S/../../runtime/record_storage_apply.py --print-apply-contract | FileCheck %s --check-prefix=APP --implicit-check-not=can-run-plan=yes
// RUN: python3 %S/../../runtime/record_storage_apply.py --print-apply-matrix | FileCheck %s --check-prefix=APPM --implicit-check-not=can-run-plan=yes

func.func @dummy() {
  return
}

// APP: apply-inhabitant gate=check
// APP: schema s2c2.storage_apply.v1
// APP: source-schema s2c2.storage_rewrite.v1
// APP: pattern W0-3/2
// APP: object-canonical 2
// APP: prose-O2-ne-object yes
// APP: candidate-id canonical-text
// APP: hash-is-candidate-id no
// APP: pi-bijective yes
// APP: hb-star not-raw-edges yes
// APP: enum-f no
// APP: search no
// APP: can-run-plan no
// APP: match-yes-applied-no allowed
// APP: match-no-applied-yes forbidden
// APP: decision-subject-rewrite-applicable no
// APP: example-applied yes
// APP: example-match yes
// APP: example-rewrite-path yes
// APP: example-can-run-plan no
// APP-NOT: can-run-plan=yes

// APPM: apply-matrix gate=check
// APPM: app-case apply-yes
// APPM: app-match yes
// APPM: app-applied yes
// APPM: app-rewrite-path yes
// APPM: app-can-run-plan no
// APPM: app-case identity-prose-o2
// APPM: app-reasons rewrite.identity-mismatch
// APPM: app-case transformation-mismatch
// APPM: app-match no
// APPM: app-reasons decision.unknown-reason
// APPM: app-case postcondition-hb
// APPM: app-match yes
// APPM: app-applied no
// APPM: app-case witness-wrong-device
// APPM: app-applied no
// APPM: app-case capacity-other
// APPM: app-match no
// APPM: app-case collide-evict
// APPM: app-match yes
// APPM: app-applied no
// APPM: app-case collide-transfer
// APPM: app-applied no
// APPM: app-case collide-restore
// APPM: app-applied no
// APPM: can-run-plan no
// APPM: enum-f no
// APPM-NOT: can-run-plan=yes
