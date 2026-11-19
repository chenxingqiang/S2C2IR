// Capacity restore-legal pair required by record_capacity.RESTORE_LEGAL.
// Query only. No semantic cut. can-run-plan stays no.
// No capacity predicates. Do not print rewrite-license=yes.
// RUN: python3 %S/../../runtime/record_restore_legal_bind.py --print-restore-legal-bind | FileCheck %s --check-prefix=RSL --implicit-check-not=rewrite-license=yes
// RSL: restore-legal-bind gate=query
// RSL: restore-legal TRANSFER,REMATERIALIZE
// RSL: restore-legal-bind yes
// RSL: can-run-plan no
