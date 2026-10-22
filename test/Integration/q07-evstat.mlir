// Evidence measurement statuses. Query only. No semantic cut.
// can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_q07_evstat.py --print-q07-evstat | FileCheck %s --check-prefix=Q07 --implicit-check-not=can-run-plan=yes
// Q07: q07-evstat gate=query
// Q07: evidence-status measured
// Q07: evidence-status inferred
// Q07: evidence-status fixture
// Q07: evidence-status pending
// Q07: evidence-status invalid
// Q07: q07-evstat yes
// Q07: can-run-plan no
