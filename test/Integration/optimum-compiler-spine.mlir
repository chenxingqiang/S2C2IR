// Optimum authorization and carrier spine handoff. Host-side contracts.
// Not a compiler E2E. Does not require s2c2-opt.
// Authorization is the unique minimum-cost legal strategy. 7A stays unchanged.
// The capacity handoff applies only when the caller supplies a witness.
// Do not FileCheck microseconds. can-run-plan stays no. next_cut stays closed.
// RUN: python3 %S/../../runtime/record_optimum_authorization.py --print-optimum-authorization | FileCheck %s --check-prefix=OPT --implicit-check-not="can-run-plan yes" --implicit-check-not="next-cut OPENED" --implicit-check-not="result FAIL"
// RUN: python3 %S/../../runtime/record_compiler_spine.py --print-compiler-spine | FileCheck %s --check-prefix=SPINE --implicit-check-not="can-run-plan yes" --implicit-check-not="compiler-e2e yes" --implicit-check-not="semantic-cut yes" --implicit-check-not="s2c2-opt-bypass yes"

func.func @dummy() {
  return
}

// OPT: optimum-authorization v1
// OPT: schema s2c2.optimum_authorization.v1
// OPT: authorization-schema s2c2.authorization.v1
// OPT: optimum-ne-authorization-schema yes
// OPT: decision-schema s2c2.decision.v1
// OPT: optimum-ne-decision-schema yes
// OPT: rule unique-minimum-cost
// OPT: selected-id capacity-optimum
// OPT: cost 4
// OPT: authorized yes
// OPT: rewrite-license yes
// OPT: rewrite-plan yes
// OPT: bound-sequence KEEP:0,KEEP:1,EVICT:2,TRANSFER:2,RESTORE:2
// OPT: illegal-cheaper-not-selected yes
// OPT: tie no
// OPT: no-legal no
// OPT: frozen-7a-policy-missing no
// OPT: apply-match yes
// OPT: apply-can-run-plan no
// OPT: can-run-plan no
// OPT: capacity-f ssd-capacity-4tile
// OPT: capacity-plain no
// OPT: capacity-all-keep no
// OPT: capacity-restore-order no
// OPT: capacity-selected keep{0,1}|evict{2}|rematerialize{}
// OPT: capacity-bound KEEP:0,KEEP:1,EVICT:2,TRANSFER:2,RESTORE:2
// OPT: capacity-sufficient yes
// OPT: capacity-sufficient-ne-rewrite-license yes
// OPT: capacity-witness-applied no
// OPT: capacity-matches-measured-rank yes
// OPT: outside-f-ignored yes
// OPT: capacity-tie no
// OPT: capacity-plan-rewrite-license no
// OPT: seven-a-unchanged yes
// OPT: next-cut NOT-OPENED
// OPT: result PASS

// SPINE: compiler-spine gate=handoff
// SPINE: pipeline carrier-text extract evaluate-apply
// SPINE: s2c2-opt-invoked no
// SPINE: s2c2-opt-bypass no
// SPINE: s2c2-opt-has-carrier-dialect no
// SPINE: tablegen no
// SPINE: lowering no
// SPINE: evaluate-apply unchanged
// SPINE: authorization existing
// SPINE: rewrite-plan existing
// SPINE: compiler-e2e no
// SPINE: can-run-plan no
// SPINE: semantic-cut no
// SPINE: next-cut no
// SPINE: spine-match yes
// SPINE: spine-applied yes
// SPINE: opt-bypass refusal apply-not-called
// SPINE: extract-refusal apply-not-called
// SPINE: no-region refusal apply-not-called
// SPINE: other-program match no
// SPINE: other-program applied no
// SPINE: apply-called yes
// SPINE: host-matrix-through-spine 29
// SPINE: induced-hb-copied no
// SPINE: scenario-corpus-spellable 8
// SPINE: S05-fixture applied no
// SPINE: S05-carrier-only applied yes
// SPINE: carrier-encodes-induced-hb no
// SPINE: authorization-guard-overlap restored
// SPINE: default-path authorization acceptance-fixture
// SPINE: default-path witness driver-built
// SPINE: default-path caller-authorized no
// SPINE: caller-witness-missing applied-no
// SPINE: caller-witness-illegal applied-no
// SPINE: caller-witness-wrong-device applied-no
// SPINE: caller-plan-closed match-no applied-no
// SPINE: capacity-handoff same-canonical yes
// SPINE: capacity-handoff-witness-missing applied-no
// SPINE: capacity-handoff-plain applied-no
// SPINE: capacity-handoff-opt refusal apply-not-called
// SPINE: capacity-handoff-default-path unchanged
// SPINE: capacity-corpus refused-before-host 2
// SPINE: capacity-corpus host-no 4
// SPINE: capacity-corpus host-yes 3
// SPINE: capacity-corpus s05-fixture applied-no
// SPINE: capacity-corpus s05-text carrier-applies
// SPINE: capacity-corpus induced-hb-copied no
// SPINE: capacity-corpus s09-envelope-not-consumed yes
