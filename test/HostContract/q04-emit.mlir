// EMITTED_REASONS from record_storage_apply, in order.
// Query only. No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_q04_emit.py --print-q04-emit | FileCheck %s --check-prefix=Q04 --implicit-check-not=can-run-plan=yes --implicit-check-not=rewrite-license=yes
// Q04: q04-emit gate=query
// Q04: emitted decision.unknown-reason
// Q04: emitted rewrite.identity-mismatch
// Q04: emitted rewrite.sequence-mismatch
// Q04: emitted rewrite.duplicate-envelope
// Q04: emitted rewrite.license-no
// Q04: q04-emit yes
// Q04: can-run-plan no
