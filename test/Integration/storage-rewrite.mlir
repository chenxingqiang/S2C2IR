// 7B Storage Rewrite Plan. Host-side Decision contract.
// Not a compiler E2E. Does not require s2c2-opt. Not IR apply.
// rewrite-license ≠ rewrite-plan ≠ rewrite-path.
// Unique sequence KEEP → EVICT → TRANSFER → RESTORE.
// Do not FileCheck microseconds.
// RUN: python3 %S/../../runtime/record_storage_rewrite.py --print-rewrite-contract | FileCheck %s --check-prefix=REW --implicit-check-not=can-run-plan=yes --implicit-check-not=rewrite-path=yes --implicit-check-not=applied=yes
// RUN: python3 %S/../../runtime/record_storage_rewrite.py --print-rewrite-matrix | FileCheck %s --check-prefix=REWM --implicit-check-not=can-run-plan=yes --implicit-check-not=rewrite-path=yes --implicit-check-not=applied=yes

func.func @dummy() {
  return
}

// REW: rewrite-planner gate=query
// REW: schema s2c2.storage_rewrite.v1
// REW: decision-schema s2c2.decision.v1
// REW: decision-subject rewrite-plan
// REW: rewrite-identity selected-object-action-license-kind
// REW: action storage-rewrite
// REW: license-kind storage-capacity-rewrite
// REW: sequence KEEP,EVICT,TRANSFER,RESTORE
// REW: rewrite-license-ne-rewrite-plan yes
// REW: rewrite-plan-ne-rewrite-path yes
// REW: rewrite-plan-yes-ne-rewrite-path yes
// REW: rewrite-plan-yes-ne-applied yes
// REW: rewrite-plan-yes-ne-can-run-plan yes
// REW: sequence-input-not-ignored-extra yes
// REW: duplicate-sequence-safe-no yes
// REW: duplicate-envelope-safe-no yes
// REW: envelope-decision-contract yes
// REW: source-schema-consumed s2c2.decision.v1
// REW: license-identity-eq-rewrite-license-identity yes
// REW: rewrite-namespace v0.1
// REW: ea-1-authorization-tokens none
// REW: authorization-namespace frozen
// REW: host-side-decision-contract yes
// REW: compiler-e2e no
// REW: can-run-plan no
// REW: rewrite-path no
// REW: applied no
// REW: capability-schedule-ne-god-object yes
// REW: f-storage-schedule-not-inhabited yes
// REW: generic-schema-validator n/a
// REW: rewrite-matrix-cases 18
// REW: required-input authorization
// REW: sequence-input rewrite-sequence
// REW: token rewrite.license-no
// REW: token rewrite.identity-mismatch
// REW: token rewrite.sequence-mismatch
// REW: token rewrite.duplicate-envelope
// REW: token rewrite.duplicate-sequence
// REW: token rewrite.plan-closed
// REW: note six-c-m-frozen
// REW: note seven-a-frozen
// REW: note seven-b-opened
// REW: note seven-b-applied-closed
// REW-NOT: can-run-plan=yes
// REW-NOT: rewrite-path=yes
// REW-NOT: applied=yes

// REWM: rewrite-matrix gate=query
// REWM: decision-subject rewrite-plan
// REWM: rewrite-license-ne-rewrite-plan yes
// REWM: rewrite-plan-ne-rewrite-path yes
// REWM: rewrite-matrix-cases 18
// REWM: rew-case license-missing
// REWM: rew-plan subject=rewrite-plan result=no reasons=rewrite.license-no
// REWM: rew-case license-no
// REWM: rew-plan subject=rewrite-plan result=no reasons=rewrite.license-no
// REWM: rew-case authorized-no
// REWM: rew-plan subject=rewrite-plan result=no reasons=rewrite.license-no
// REWM: rew-case rewrite-plan-yes
// REWM: rew-plan subject=rewrite-plan result=yes reasons=rewrite.plan-closed
// REWM: rew-sequence KEEP,EVICT,TRANSFER,RESTORE
// REWM: rew-transformation keep-evict-transfer-restore
// REWM: rew-applied no
// REWM: rew-rewrite-path no
// REWM: rew-case matching-sequence
// REWM: rew-envelope-inputs authorization,rewrite-sequence
// REWM: rew-plan subject=rewrite-plan result=yes reasons=rewrite.plan-closed
// REWM: rew-case selected-mismatch
// REWM: rew-plan subject=rewrite-plan result=no reasons=rewrite.identity-mismatch
// REWM: rew-case object-mismatch
// REWM: rew-plan subject=rewrite-plan result=no reasons=rewrite.identity-mismatch
// REWM: rew-case action-mismatch
// REWM: rew-plan subject=rewrite-plan result=no reasons=rewrite.identity-mismatch
// REWM: rew-case license-kind-mismatch
// REWM: rew-plan subject=rewrite-plan result=no reasons=rewrite.identity-mismatch
// REWM: rew-case wrong-sequence
// REWM: rew-plan subject=rewrite-plan result=no reasons=rewrite.sequence-mismatch
// REWM: rew-case duplicate-sequence
// REWM: rew-envelope-inputs authorization,rewrite-sequence,rewrite-sequence
// REWM: rew-plan subject=rewrite-plan result=no reasons=rewrite.duplicate-sequence
// REWM: rew-case duplicate-envelope
// REWM: rew-plan subject=rewrite-plan result=no reasons=rewrite.duplicate-envelope
// REWM: rew-case unknown-schema
// REWM: rew-plan subject=rewrite-plan result=no reasons=decision.unknown-reason
// REWM: rew-case extras-ignored
// REWM: rew-envelope-inputs authorization,cost-rank
// REWM: rew-plan subject=rewrite-plan result=yes reasons=rewrite.plan-closed
// REWM: rew-applied no
// REWM: rew-rewrite-path no
// REWM: rew-case malformed-authorized
// REWM: rew-plan subject=rewrite-plan result=no reasons=decision.unknown-reason
// REWM: rew-case malformed-rewrite-license
// REWM: rew-plan subject=rewrite-plan result=no reasons=decision.unknown-reason
// REWM: rew-case source-schema-mismatch
// REWM: rew-plan subject=rewrite-plan result=no reasons=decision.unknown-reason
// REWM: rew-case license-identity-drift
// REWM: rew-plan subject=rewrite-plan result=no reasons=rewrite.identity-mismatch
// REWM: can-run-plan no
// REWM: rewrite-path no
// REWM: applied no
// REWM-NOT: can-run-plan=yes
// REWM-NOT: rewrite-path=yes
// REWM-NOT: applied=yes
