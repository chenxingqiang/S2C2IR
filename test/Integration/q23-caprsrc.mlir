// Capacity restore source fields required by record_capacity.RESTORE_SRC_FIELDS.
// Query only. No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_q23_caprsrc.py --print-q23-caprsrc | FileCheck %s --check-prefix=Q23 --implicit-check-not=can-run-plan=yes
// Q23: q23-caprsrc gate=query
// Q23: restore-src-field object
// Q23: restore-src-field space
// Q23: restore-src-field kind
// Q23: q23-caprsrc yes
// Q23: can-run-plan no
