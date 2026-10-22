// S0 and S1 selection strings must match on suf, auth, rew, and apply.
// This lit test is not in check-host. No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_selected_s0_bind.py --print-selected-s0-bind | FileCheck %s --check-prefix=SS0 --implicit-check-not="can-run-plan yes" --implicit-check-not="semantic-cut yes"
// SS0: selected-s0-bind gate=query
// SS0: selected-s0 keep{0,1}|evict{2}|rematerialize{}
// SS0: selected-s1 keep{1,2}|evict{0}|rematerialize{}
// SS0: selected-s0-bind yes
// SS0: can-run-plan no
