// Require the sufficiency required predicates and ignored extras.
// Counts and joins come from the tuples. Not in check-host.
// No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_suf_required_bind.py --print-suf-required-bind | FileCheck %s --check-prefix=SRQ --implicit-check-not='decision-subject sufficient' --implicit-check-not=can-run-plan=yes
// SRQ: suf-required-bind gate=query
// SRQ: required-count 4
// SRQ: ignored-extra applicable,authorized
// SRQ: results yes,no,n/a
// SRQ: suf-required-bind yes
// SRQ: can-run-plan no
