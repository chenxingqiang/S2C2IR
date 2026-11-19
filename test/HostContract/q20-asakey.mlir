// Ascend analyze keys on the hardware ledger. Query only. No semantic cut.
// can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_q20_asakey.py --print-q20-asakey | FileCheck %s --check-prefix=Q20 --implicit-check-not=can-run-plan=yes
// Q20: q20-asakey gate=query
// Q20: analyze cap-schema --analyze-cap-schema
// Q20: analyze mem --analyze-mem
// Q20: analyze cc-phase --analyze-cc-phase
// Q20: analyze cc-size --analyze-cc-size
// Q20: analyze cc-rewrite --analyze-cc-rewrite
// Q20: analyze ssd-mlp-wallclock --analyze-ssd-mlp-wallclock
// Q20: analyze e2e-gain --analyze-e2e-gain
// Q20: q20-asakey yes
// Q20: can-run-plan no
