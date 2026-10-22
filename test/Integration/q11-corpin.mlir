// Query the frozen scenario-corpus identity pins.
// No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_q11_corpin.py --print-q11-corpin | FileCheck %s --check-prefix=Q11 --implicit-check-not=can-run-plan=yes

func.func @dummy() {
  return
}

// Q11: q11-corpin gate=query
// Q11: corpus-id w0-3-2-scenario-corpus-v1
// Q11: corpus-baseline 71a6880dbaaac929bac837af0b7fbcad78708bb4
// Q11: corpus-fingerprint 52bf4be9680046a725f9f79c7abf2d045efbd7d03b3cb87a355419b67a7a0d00
// Q11: q11-corpin yes
// Q11: can-run-plan no
