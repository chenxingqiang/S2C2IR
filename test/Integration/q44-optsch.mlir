// Optimum, authorization, and decision schemas stay distinct.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host.
// RUN: python3 %S/../../runtime/record_q44_optsch.py --print-q44-optsch | FileCheck %s --check-prefix=Q44 --implicit-check-not=can-run-plan=yes --implicit-check-not=authorization=yes
// Q44: q44-optsch gate=query
// Q44: optimum-schema s2c2.optimum_authorization.v1
// Q44: authorization-schema s2c2.authorization.v1
// Q44: decision-schema s2c2.decision.v1
// Q44: q44-optsch yes
// Q44: can-run-plan no
