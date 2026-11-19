// Host matrix counts for authorization, sufficiency, and rewrite.
// Lengths come from the case lists. This lit test is not in check-host.
// No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_auth_matrix_count.py --print-auth-matrix-counts | FileCheck %s --check-prefix=AMC

func.func @dummy() {
  return
}

// AMC: auth-matrix-counts gate=query
// AMC: authorization-matrix-cases 20
// AMC: sufficiency-matrix-cases 16
// AMC: rewrite-matrix-cases 18
// AMC: auth-matrix-counts-bound yes
// AMC: can-run-plan no
