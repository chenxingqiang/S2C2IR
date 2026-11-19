// Apply window forbidden and allowed op sets. Query only. No semantic cut.
// can-run-plan stays no. Do not print applied=yes.
// RUN: python3 %S/../../runtime/record_window_ops_bind.py --print-window-ops-bind | FileCheck %s --check-prefix=WIN --implicit-check-not=applied=yes --implicit-check-not="can-run-plan yes" --implicit-check-not="semantic-cut yes"
// WIN: window-ops-bind gate=query
// WIN: forbidden-count 6
// WIN: allowed-other-count 2
// WIN: window-ops-bind yes
// WIN: can-run-plan no
