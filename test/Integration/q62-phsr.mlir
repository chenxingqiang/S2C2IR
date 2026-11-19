// RUN: python3 %S/../../runtime/record_q62_phsr.py --print-q62-phsr | FileCheck %s --check-prefix=Q62 --implicit-check-not=can-run-plan=yes
// Q62: q62-phsr gate=query
// Q62: phase-r 0.01
// Q62: phase-r 0.03
// Q62: phase-r 0.1
// Q62: phase-r 0.3
// Q62: phase-r 1.0
// Q62: phase-r 3.0
// Q62: phase-r 10.0
// Q62: phase-r 30.0
// Q62: phase-k-max 4096
// Q62: q62-phsr yes
// Q62: can-run-plan no
