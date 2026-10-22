// Profile constraint statuses. Read CONSTRAINT_STATUSES from the profile host.
// This lit test is not in check-host. No semantic cut. can-run-plan stays no.
// Do not add statuses. Do not FileCheck microseconds. This file does not require s2c2-opt.
// RUN: python3 %S/../../runtime/record_profile_status_bind.py --print-profile-status-bind | FileCheck %s --check-prefix=PST --implicit-check-not=can-run-plan=yes --implicit-check-not="semantic-cut yes"

func.func @dummy() {
  return
}

// PST: gate=query
// PST: constraint allowed
// PST: constraint forbidden
// PST: constraint not-applicable
// PST: constraint unproven
// PST: profile-status-bind yes
// PST: can-run-plan no
