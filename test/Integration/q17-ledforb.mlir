// Hardware ledger forbid count. Query only. Does not call run_analyzer.
// No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_q17_ledforb.py --print-q17-ledforb | FileCheck %s --check-prefix=Q17 --implicit-check-not=can-run-plan=yes --implicit-check-not=password
// Q17: q17-ledforb gate=query
// Q17: ledger-forbid-count 1
// Q17: q17-ledforb yes
// Q17: can-run-plan no
