// Semantic Baseline v1. Replay frozen Decision hosts after
// #136 / #137 / #138 landed. No new semantics. Not IR apply.
// #139 not merged. Apply inhabitant CLOSED.
// Do not FileCheck microseconds.
// RUN: python3 %S/../../runtime/record_semantic_baseline.py --print-semantic-baseline-contract | FileCheck %s --check-prefix=BASE --implicit-check-not=can-run-plan=yes --implicit-check-not=rewrite-path=yes --implicit-check-not=applied=yes
// RUN: python3 %S/../../runtime/record_semantic_baseline.py --print-semantic-baseline-summary | FileCheck %s --check-prefix=SUM --implicit-check-not=can-run-plan=yes --implicit-check-not=rewrite-path=yes --implicit-check-not=applied=yes

func.func @dummy() {
  return
}

// BASE: semantic-baseline-v1 gate=query
// BASE: checkpoint verification-only
// BASE: semantic-expansion none
// BASE: main-merge 136
// BASE: main-merge 137
// BASE: main-merge 138
// BASE: main-merge-139 no
// BASE: apply-inhabitant closed
// BASE: decision-stack usable
// BASE: decision-stack sufficient
// BASE: decision-stack authorized
// BASE: decision-stack rewrite-license
// BASE: decision-stack rewrite-plan
// BASE: ea-1-subject usable
// BASE: ea-1-still-usable-only yes
// BASE: sufficiency-matrix-cases 16
// BASE: authorization-matrix-cases 20
// BASE: rewrite-matrix-cases 18
// BASE: legacy-rce pass
// BASE: legacy-xid pass
// BASE: apply-contract specification-only
// BASE: apply-contract-on-main no
// BASE: ir-mutation none
// BASE: f-storage-schedule none
// BASE: producer ea-1 usable
// BASE: producer sufficiency sufficient
// BASE: producer authorization authorized
// BASE: producer authorization rewrite-license
// BASE: producer rewrite-planner rewrite-plan
// BASE: can-run-plan no
// BASE: rewrite-path no
// BASE: applied no
// BASE: note apply-not-merged
// BASE: note apply-inhabitant-closed
// BASE-NOT: rewrite-path=yes
// BASE-NOT: applied=yes
// BASE-NOT: can-run-plan=yes

// SUM: semantic-baseline-v1-summary gate=query
// SUM: layer EA-1 result=usable
// SUM: layer 6C-M result=sufficient
// SUM: layer 7A result=authorized,rewrite-license
// SUM: layer 7B result=rewrite-plan
// SUM: layer apply-contract result=specification-only merged=no
// SUM: layer ir-mutation result=none
// SUM: failure-class semantic-vs-execution yes
// SUM: can-run-plan no
// SUM: rewrite-path no
// SUM: applied no
// SUM-NOT: rewrite-path=yes
// SUM-NOT: applied=yes
// SUM-NOT: can-run-plan=yes
