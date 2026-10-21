// Goal Alignment v1. The dialect surface matches include/s2c2.
// Sketch ops stay absent. can-run-plan stays no. next_cut stays closed.
// RUN: python3 %S/../../runtime/record_goal_alignment.py --print-goal-alignment | FileCheck %s --check-prefix=GOAL --implicit-check-not="can-run-plan yes" --implicit-check-not="semantic-cut yes" --implicit-check-not="next-cut OPENED" --implicit-check-not="sketch-ops present"

module {
}

// GOAL: goal-alignment PASS
// GOAL: source include/s2c2
// GOAL: page docs/design/goal-alignment-v1.md
// GOAL: stor-ops 7
// GOAL: comp-ops 3
// GOAL: comm-ops 3
// GOAL: sched-ops 7
// GOAL: sketch-ops absent
// GOAL: can-run-plan no
// GOAL: carrier-file runtime/record_mlir_carrier.py
// GOAL: carrier-separate yes
// GOAL: host W0-3/2
// GOAL: next-cut NOT-OPENED
// GOAL: readme linked
// GOAL: status-slides 3
// GOAL: semantic-cut no
