// Scenario-corpus YES and NO from record_scenario_corpus.
// Query only. This lit test is not in check-host. No semantic cut.
// can-run-plan stays no. Does not call run_analyzer.
// RUN: python3 %S/../../runtime/record_q99_yesno.py --print-q99-yesno | FileCheck %s --check-prefix=Q99 --implicit-check-not=can-run-plan=yes
// Q99: q99-yesno gate=query
// Q99: corpus-yes yes
// Q99: corpus-no no
// Q99: q99-yesno yes
// Q99: can-run-plan no
