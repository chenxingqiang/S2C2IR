// Scenario Corpus v1. Frozen W0-3/2 behavior fingerprint.
// Not a new contract. Not compiler E2E.
// RUN: python3 %S/../../runtime/record_scenario_corpus.py --print-scenario-corpus | FileCheck %s --check-prefix=SCN --implicit-check-not=can-run-plan=yes

func.func @dummy() {
  return
}

// SCN: scenario-corpus gate=v1
// SCN: baseline 71a6880dbaaac929bac837af0b7fbcad78708bb4
// SCN: corpus-id w0-3-2-scenario-corpus-v1
// SCN: anchor w0-3-2-storage-capacity-001
// SCN: contract-changed no
// SCN: inhabitant-changed no
// SCN: compiler-e2e no
// SCN: s2c2-opt no
// SCN: enum-f no
// SCN: search no
// SCN: authorization-reopened no
// SCN: semantic-cut no
// SCN: can-run-plan no
// SCN: scene-count 10
// SCN: S01 canonical-success match=yes applied=yes rewrite-path=yes can-run-plan=no reasons=none result=7e5293b0780b584c23b0320a25d9b96b0917cc220137a8ec8fd2571121a3d5e7
// SCN: S02 keep-order match=no applied=no rewrite-path=no can-run-plan=no reasons=rewrite.identity-mismatch result=45dec8fc204d8bc19eaf0869f6fc7f928ccf80bdf0527c5e7a49d65538fbbe33
// SCN: S03 multi-region match=no applied=no rewrite-path=no can-run-plan=no reasons=none result=28a1a4a578fd57fdb626d6e0fa741ebef7d5f3bd19037844d8f7a2089df6e0a7
// SCN: S04 cross-block match=no applied=no rewrite-path=no can-run-plan=no reasons=none result=48ccd5c20a8146f6cad183e9f770337a27ea17adfc3bbf31681cd9048b4f5bcc
// SCN: S05 hb-violation match=yes applied=no rewrite-path=no can-run-plan=no reasons=none result=9504f1805cc3a6427c580be504d67a13645de236464c256ebbc856e4708f2d9e
// SCN: S06 missing-witness match=yes applied=no rewrite-path=no can-run-plan=no reasons=none result=53dd047f769895f90a692d5ed4879f9474744bfa93c1b96f81ff598f42d73328
// SCN: S07 wrong-device match=yes applied=no rewrite-path=no can-run-plan=no reasons=none result=53dd047f769895f90a692d5ed4879f9474744bfa93c1b96f81ff598f42d73328
// SCN: S08 opid-collision match=yes applied=no rewrite-path=no can-run-plan=no reasons=none result=d5ff06aa86b9d47915995c8ed73edfdad3435b65086a7645771481f220ebdcf9
// SCN: S09 transformation-mismatch match=no applied=no rewrite-path=no can-run-plan=no reasons=decision.unknown-reason result=53dd047f769895f90a692d5ed4879f9474744bfa93c1b96f81ff598f42d73328
// SCN: S10 source-envelope-immutability source-unchanged=yes envelope-unchanged=yes double-run=equal
// SCN: boundary authorization-reopened=no
// SCN: fingerprint 52bf4be9680046a725f9f79c7abf2d045efbd7d03b3cb87a355419b67a7a0d00
// SCN: corpus-result PASS
// SCN-NOT: can-run-plan=yes
