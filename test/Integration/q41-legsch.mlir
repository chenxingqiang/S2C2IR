// Legality schema stays distinct from the profile and checking schemas.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host.
// RUN: python3 %S/../../runtime/record_q41_legsch.py --print-q41-legsch | FileCheck %s --check-prefix=Q41 --implicit-check-not=can-run-plan=yes
// Q41: q41-legsch gate=query
// Q41: legality-schema s2c2.realization_legality.v1
// Q41: profile-schema s2c2.capability_profile.v1
// Q41: checking-schema s2c2.realization_checking.v1
// Q41: q41-legsch yes
// Q41: can-run-plan no
