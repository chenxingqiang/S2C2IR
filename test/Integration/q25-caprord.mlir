// Capacity restore-order fields required by record_capacity.RESTORE_ORDER_FIELDS.
// Query only. No semantic cut. can-run-plan stays no.
// No capacity predicate, device, dialect, backend, or semantic cut.
// RUN: python3 %S/../../runtime/record_q25_caprord.py --print-q25-caprord | FileCheck %s --check-prefix=Q25 --implicit-check-not=can-run-plan=yes
// Q25: q25-caprord gate=query
// Q25: restore-order-field object
// Q25: restore-order-field before
// Q25: restore-order-field witness
// Q25: restore-order-field scope
// Q25: q25-caprord yes
// Q25: can-run-plan no
