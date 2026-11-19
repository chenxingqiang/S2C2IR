// Table-driven constant audit for the Python host stack. Query only.
// One row per fact previously pinned by the per-constant reader
// scripts (record_*_bind.py / record_q*.py) and their lit files.
// The printer never echoes audited values. No semantic cut.
// can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_constant_audit.py --print-constant-audit | FileCheck %s --check-prefix=CA --implicit-check-not=can-run-plan=yes --implicit-check-not=password --implicit-check-not='next-cut OPENED'
// CA: constant-audit gate=query
// CA: constant-audit-total {{[0-9]+}}
// CA: constant-audit-failed 0
// CA: constant-audit yes
// CA: can-run-plan no
