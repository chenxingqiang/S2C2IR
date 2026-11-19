// Sketch ops stay out of the TableGen dialects.
// Query only. No semantic cut. can-run-plan stays no. Do not add ops.
// RUN: python3 %S/../../runtime/record_td_absent_bind.py --print-td-absent-bind | FileCheck %s --check-prefix=TDA --implicit-check-not="can-run-plan yes" --implicit-check-not="semantic-cut yes" --implicit-check-not="sketch-ops present"

module {
}

// TDA: td-absent-bind gate=query
// TDA: sketch-ops absent
// TDA: td-absent-bind yes
// TDA: can-run-plan no
