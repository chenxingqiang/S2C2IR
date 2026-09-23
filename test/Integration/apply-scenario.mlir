// Acceptance scenario w0-3-2-storage-capacity-001.
// Host-level inhabitant evidence. Not compiler E2E.
// Do not FileCheck microseconds.
// RUN: python3 %S/../../runtime/record_apply_scenario.py --print-apply-scenario | FileCheck %s --check-prefix=SCN --implicit-check-not=can-run-plan=yes

func.func @dummy() {
  return
}

// SCN: apply-scenario gate=acceptance
// SCN: scenario-id w0-3-2-storage-capacity-001
// SCN: evidence-scope contract-level-e2e
// SCN: evidence-scope host-inhabitant
// SCN: compiler-e2e no
// SCN: s2c2-opt no
// SCN: hardware-execution no
// SCN: enum-f no
// SCN: search no
// SCN: can-run-plan no
// SCN: scenario-match yes
// SCN: scenario-applied yes
// SCN: scenario-rewrite-path yes
// SCN: scenario-can-run-plan no
// SCN: candidate-id-is-canonical yes
// SCN: canonical-p-sha256 53dd047f769895f90a692d5ed4879f9474744bfa93c1b96f81ff598f42d73328
// SCN: canonical-p-prime-sha256 7e5293b0780b584c23b0320a25d9b96b0917cc220137a8ec8fd2571121a3d5e7
// SCN: failure identity-mismatch match=no applied=no reasons=rewrite.identity-mismatch
// SCN: failure multiple-region match=no applied=no reasons=none
// SCN: failure hb-mismatch match=yes applied=no reasons=none
// SCN: failure witness-missing match=yes applied=no reasons=none
// SCN: failure wrong-device match=yes applied=no reasons=none
// SCN: failure opid-collision match=yes applied=no reasons=none
// SCN: real-semantic-gap none
// SCN: next-cut no
// SCN-NOT: can-run-plan=yes
