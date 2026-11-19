// Owner decisions 3A and 5A. Recording them does not open the cut.
// The witness stays external. A missing witness stays unapplied.
// No new op. The carrier stays out of s2c2-opt. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_7c_owner.py --print-7c-owner | FileCheck %s --check-prefix=OWN --implicit-check-not="can-run-plan yes" --implicit-check-not="can-run-plan=yes" --implicit-check-not="next-cut OPENED" --implicit-check-not="applied=yes"

func.func @dummy() {
  return
}

// OWN: 7c-owner gate=record
// OWN: decision-3 3A
// OWN: witness-source external
// OWN: witness-missing applied=no
// OWN: decision-5 5A
// OWN: connectivity-amendment recorded
// OWN: amendment-opens-cut no
// OWN: next-cut NOT-OPENED
// OWN: can-run-plan no
// OWN: carrier-in-s2c2-opt no
// OWN: ops-added no
// OWN: 7d-opened no
// OWN: 7e-opened no
// OWN: 7f-opened no
// OWN: 8a-opened no
// OWN: 7c-owner yes
