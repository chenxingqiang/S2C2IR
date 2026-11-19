// Loaded ledger rows. Query only. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_ledger_rows_bind.py --print-ledger-rows-bind | FileCheck %s --check-prefix=LRB --implicit-check-not=password --implicit-check-not="can-run-plan yes"
// LRB: ledger-rows-bind gate=query
// LRB: ledger-records 31
// LRB: ledger-hardware rtx4090,ascend910b
// LRB: ledger-rows-bind yes
// LRB: can-run-plan no
// LRB-NOT: password
