// Capability profile schema stays distinct from the applicability schema.
// Query only. No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_q42_prfsch.py --print-q42-prfsch | FileCheck %s --check-prefix=Q42 --implicit-check-not=can-run-plan=yes
// Q42: q42-prfsch gate=query
// Q42: profile-schema s2c2.capability_profile.v1
// Q42: applicability-schema s2c2.capability_applicability.v1
// Q42: q42-prfsch yes
// Q42: can-run-plan no
