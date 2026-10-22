// TableGen op counts bound to the goal-alignment check. Query only.
// No semantic cut. can-run-plan stays no. next_cut stays NOT OPENED.
// RUN: python3 %S/../../runtime/record_dialect_count_bind.py --print-dialect-count-bind | FileCheck %s --check-prefix=DIA
// DIA: dialect-count-bind gate=query
// DIA: stor-ops 7
// DIA: comp-ops 3
// DIA: comm-ops 3
// DIA: sched-ops 7
// DIA: dialect-count-bind yes
// DIA: can-run-plan no
