// Canonical unknown-scope differs from the occupancy printer.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Does not call run_analyzer.
// RUN: python3 %S/../../runtime/record_q39_candisp.py --print-q39-candisp | FileCheck %s --check-prefix=Q39 --implicit-check-not=can-run-plan=yes
// Q39: q39-candisp gate=query
// Q39: canonical-display-count 13
// Q39: canonical-unknown-scope evidence.unknown-scope
// Q39: printer-unknown-scope evidence.scope-mismatch
// Q39: canonical-ne-printer yes
// Q39: q39-candisp yes
// Q39: can-run-plan no
