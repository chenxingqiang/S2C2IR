// Canonical source and prime programs from record_apply_scenario.
// Query only. This lit test is not in check-host. No semantic cut.
// can-run-plan stays no. Do not print the program texts.
// RUN: python3 %S/../../runtime/record_q47_canprg.py --print-q47-canprg | FileCheck %s --check-prefix=Q47 --implicit-check-not=can-run-plan=yes --implicit-check-not=applied=yes
// Q47: q47-canprg gate=query
// Q47: source-len 206
// Q47: prime-len 380
// Q47: canonical-differ yes
// Q47: q47-canprg yes
// Q47: can-run-plan no
