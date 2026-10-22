// ACTION_V01 is storage-rewrite on auth, rew, and apply.
// Query only. No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_action_v01_bind.py --print-action-v01-bind | FileCheck %s --check-prefix=ACT --implicit-check-not=can-run-plan=yes
// ACT: action-v01-bind gate=query
// ACT: action storage-rewrite
// ACT: action-v01-bind yes
// ACT: can-run-plan no
