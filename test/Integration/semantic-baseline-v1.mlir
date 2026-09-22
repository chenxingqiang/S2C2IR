// Semantic Baseline v1. Replay frozen Decision hosts.
// #139 is merged. The apply host may exist.
// This replay does not execute Apply.
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
// BASE: main-merge 139
// BASE: apply-host present
// BASE: baseline-replay-executes-apply no
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
// BASE: apply-contract merged
// BASE: apply-contract-on-main yes
// BASE: ir-mutation-by-replay none
// BASE: f-storage-schedule none
// BASE: producer ea-1 usable
// BASE: producer sufficiency sufficient
// BASE: producer authorization authorized
// BASE: producer authorization rewrite-license
// BASE: producer rewrite-planner rewrite-plan
// BASE: can-run-plan no
// BASE: rewrite-path no
// BASE: applied no
// BASE: note apply-contract-merged
// BASE: note baseline-does-not-execute-apply
// BASE: pin usable-and-applicable-ne-sufficient yes
// BASE: pin sufficient-yes-policy-missing authorized=no
// BASE: pin authorized-yes-license-missing rewrite-license=no
// BASE: pin rewrite-plan-yes applied=no
// BASE: guard baseline-skips-apply-host yes
// BASE: guard applySchedule frozen-capability-schedule-only
// BASE: result PASS
// BASE: Semantic Baseline v1 = PASS
// BASE-NOT: rewrite-path=yes
// BASE-NOT: applied=yes
// BASE-NOT: can-run-plan=yes

// SUM: semantic-baseline-v1-summary gate=query
// SUM: EA-1
// SUM:   producer = record_decision.py
// SUM:   subject  = usable
// SUM: 6C-M
// SUM:   producer = record_sufficiency.py
// SUM:   subject  = sufficient
// SUM: 7A
// SUM:   producer = record_authorization.py
// SUM:   subjects = authorized + rewrite-license
// SUM: 7B
// SUM:   producer = record_storage_rewrite.py
// SUM:   subject  = rewrite-plan
// SUM: Apply
// SUM:   producer = record_storage_apply.py
// SUM:   status   = not-replayed
// SUM: layer EA-1 result=usable
// SUM: layer 6C-M result=sufficient
// SUM: layer 7A result=authorized,rewrite-license
// SUM: layer 7B result=rewrite-plan
// SUM: layer apply-contract result=merged
// SUM: layer apply-host present replay=no
// SUM: layer ir-mutation-by-replay result=none
// SUM: failure-class semantic-vs-execution yes
// SUM: can-run-plan no
// SUM: rewrite-path no
// SUM: applied no
// SUM: Semantic Baseline v1 = PASS
// SUM-NOT: rewrite-path=yes
// SUM-NOT: applied=yes
// SUM-NOT: can-run-plan=yes
