// Ascend SEQ_SLACK stays 1.05. Query only.
// No semantic cut. can-run-plan stays no.
// This lit test is not in check-host.
// RUN: python3 %S/../../runtime/record_q81_slack.py --print-q81-slack | FileCheck %s --check-prefix=Q81 --implicit-check-not=can-run-plan=yes
// Q81: q81-slack gate=query
// Q81: seq-slack 1.05
// Q81: q81-slack yes
// Q81: can-run-plan no
