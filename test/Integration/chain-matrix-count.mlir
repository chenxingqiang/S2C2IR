// Chain matrix counts. Read the frozen e2e and xid case lists.
// No semantic cut. can-run-plan stays no. Do not add cases.
// Do not FileCheck microseconds. This file does not require s2c2-opt.
// RUN: python3 %S/../../runtime/record_chain_matrix_count.py --print-chain-matrix-counts | FileCheck %s --check-prefix=CMC --implicit-check-not=can-run-plan=yes

func.func @dummy() {
  return
}

// CMC: chain-matrix-counts gate=query
// CMC: e2e-matrix-cases 3
// CMC: xid-matrix-cases 4
// CMC: chain-matrix-counts-bound yes
// CMC: can-run-plan no
