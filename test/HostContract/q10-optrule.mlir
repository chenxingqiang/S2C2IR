// Optimum authorization schema and unique-minimum-cost rule.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host.
// RUN: python3 %S/../../runtime/record_q10_optrule.py --print-q10-optrule | FileCheck %s --check-prefix=Q10 --implicit-check-not=can-run-plan=yes --implicit-check-not=authorization=yes
// Q10: q10-optrule gate=query
// Q10: optimum-schema s2c2.optimum_authorization.v1
// Q10: optimum-rule unique-minimum-cost
// Q10: q10-optrule yes
// Q10: can-run-plan no
