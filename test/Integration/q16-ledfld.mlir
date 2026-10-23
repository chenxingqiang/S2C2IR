// RUN: python3 %S/../../runtime/record_q16_ledfld.py --print-q16-ledfld | FileCheck %s --check-prefix=Q16 --implicit-check-not=can-run-plan=yes
// Q16: q16-ledfld gate=query
// Q16: ledger-field id
// Q16: ledger-field hardware
// Q16: ledger-field kind
// Q16: ledger-field status
// Q16: ledger-field path
// Q16: ledger-field tool
// Q16: ledger-field analyze
// Q16: ledger-field catalog_role
// Q16: ledger-field note
// Q16: ledger-field cost
// Q16: ledger-field semantics
// Q16: q16-ledfld yes
// Q16: can-run-plan no
