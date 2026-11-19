// Claim schema and checking schema from record_realization_checking.
// This lit test is not in check-host. No semantic cut. can-run-plan stays no.
// Do not FileCheck microseconds. This file does not require s2c2-opt.
// RUN: python3 %S/../../runtime/record_q40_clmsch.py --print-q40-clmsch | FileCheck %s --check-prefix=Q40 --implicit-check-not=can-run-plan=yes
// Q40: q40-clmsch gate=query
// Q40: claim-schema s2c2.realization_claim.v1
// Q40: checking-schema s2c2.realization_checking.v1
// Q40: q40-clmsch yes
// Q40: can-run-plan no
