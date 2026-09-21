// Cross-identity Checking E2E v0. Compose frozen hosts only.
// Not sufficient, not can-run-plan, not rewrite.
// Do not FileCheck microseconds. This file does not require s2c2-opt.
// RUN: python3 %S/../../runtime/record_realization_checking_xid.py --print-realization-checking-xid-contract | FileCheck %s --check-prefix=XID --implicit-check-not='decision-subject sufficient' --implicit-check-not=can-run-plan=yes
// RUN: python3 %S/../../runtime/record_realization_checking_xid.py --print-realization-checking-xid-matrix | FileCheck %s --check-prefix=XIDM --implicit-check-not='subject=sufficient' --implicit-check-not=can-run-plan=yes --implicit-check-not='rewrite-license=yes'

func.func @dummy() {
  return
}

// XID: realization-checking-xid gate=query
// XID: xid-type integration-reproducibility
// XID: semantic-expansion none
// XID: xid-chain evidence-profile-legality-claim-checking
// XID: xid-uses-frozen-hosts yes
// XID: xid-reimplements-mapping no
// XID: xid-eq-check-v0 yes
// XID: xid-identities cuda,ascend,cpu
// XID: xid-invents-npu-cim no
// XID: unclaimed-kind-ne-violation yes
// XID: contract-error-ne-result yes
// XID: can-run-plan no
// XID: sufficiency-evaluation n/a
// XID: rewrite-license no
// XID: rewrite-path no
// XID: capability-schedule-ne-god-object yes
// XID: xid-matrix-cases 4
// XID: note sufficient-decision-not-emitted

// XID-NOT: rewrite-license=yes
// XID-NOT: sufficient=yes
// XID-NOT: can-run-plan=yes
// XID-NOT: decision-subject sufficient
// XID-NOT: target=npu
// XID-NOT: target=cim

// XIDM: realization-checking-xid-matrix gate=query
// XIDM: xid-eq-check-v0 yes
// XIDM: unclaimed-kind-ne-violation yes
// XIDM: xid-invents-npu-cim no
// XIDM: xid-matrix-cases 4
// XIDM: xid-case cuda-legal
// XIDM: xid-status ok
// XIDM: xid-profile schema=s2c2.capability_profile.v1 target=cuda device=sm89:rtx4090
// XIDM: xid-finding kind=concurrent-pair result=satisfy constraint=allowed
// XIDM: xid-finding kind=staged-dma result=unproven constraint=unproven
// XIDM: xid-can-run-plan no
// XIDM: xid-case ascend-dma
// XIDM: xid-status ok
// XIDM: xid-profile schema=s2c2.capability_profile.v1 target=ascend device=ascend910b
// XIDM: xid-finding kind=concurrent-pair result=unproven constraint=unproven
// XIDM: xid-finding kind=staged-dma result=satisfy constraint=allowed
// XIDM: xid-case cpu-na
// XIDM: xid-status ok
// XIDM: xid-profile schema=s2c2.capability_profile.v1 target=cpu device=host
// XIDM: xid-finding kind=concurrent-pair result=violate constraint=not-applicable
// XIDM: xid-case cross-target
// XIDM: xid-status contract-error
// XIDM: xid-claim-identity target=cuda device=sm89:rtx4090
// XIDM: xid-error identity-mismatch
// XIDM: xid-findings-count 0
// XIDM: rewrite-license no
// XIDM: can-run-plan no
// XIDM-NOT: rewrite-license=yes
// XIDM-NOT: sufficient=yes
// XIDM-NOT: subject=sufficient
// XIDM-NOT: can-run-plan=yes
// XIDM-NOT: kind=named-nonblocking
// XIDM-NOT: target=npu
// XIDM-NOT: target=cim
