// MLIR carrier v0 extract. Host-side syntax projection.
// Not a compiler E2E. Does not require s2c2-opt. TableGen stays absent.
// C03 yes/yes is the acceptance extract. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_mlir_carrier.py --print-carrier-extract | FileCheck %s --check-prefix=CAR --implicit-check-not="can-run-plan yes" --implicit-check-not="compiler-e2e yes" --implicit-check-not="semantic-cut yes" --implicit-check-not="s2c2-opt yes" --implicit-check-not="next-cut yes"

module {
}

// CAR: mlir-carrier gate=extract-v0
// CAR: carrier syntax-only
// CAR: carrier-ne-semantic-model yes
// CAR: tablegen no
// CAR: lowering no
// CAR: evaluate-apply unchanged
// CAR: compiler-e2e no
// CAR: s2c2-opt no
// CAR: can-run-plan no
// CAR: semantic-cut no
// CAR: next-cut no
// CAR: C01 canonical-p
// CAR: C02 same-dict
// CAR: C03 yes/yes
// CAR: C04 refusal missing-op-id apply-not-called
// CAR: C05 refusal missing-capacity apply-not-called
// CAR: C06 refusal closed-set apply-not-called
// CAR: C07 refusal zero-block apply-not-called
// CAR: C08 host match=no applied=no
// CAR: C09 host match=no applied=no
// CAR: C10 host match=no applied=no blocks-not-merged
// CAR: C11 host reasons=rewrite.sequence-mismatch
// CAR: C12 host match=yes applied=no
// CAR: C13 host match=yes applied=no
// CAR: C14 host match=yes applied=no induced-not-extracted
// CAR: C15 host reasons=rewrite.identity-mismatch
// CAR: C16 host match=yes applied=no
// CAR: extract-refusal not-one-module apply-not-called
// CAR: extract-refusal fact-outside-block apply-not-called
// CAR: extract-refusal hb-outside-block apply-not-called
// CAR: extract-refusal missing-name apply-not-called
// CAR: extract-refusal missing-op apply-not-called
// CAR: extract-refusal missing-hb-from apply-not-called
// CAR: extract-refusal missing-hb-to apply-not-called
// CAR: extract-refusal missing-working-set apply-not-called
// CAR: extract-refusal not-i64 apply-not-called
// CAR: extract-refusal nested-region apply-not-called
// CAR: extract-refusal router-result closed-set apply-not-called
// CAR: host-matrix-cases 29
// CAR: host-matrix-through-carrier 29
