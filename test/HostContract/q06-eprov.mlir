// Entry provenance is the capability provenance values plus missing.
// Query only. No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_q06_eprov.py --print-q06-eprov | FileCheck %s --check-prefix=Q06 --implicit-check-not=can-run-plan=yes
// Q06: q06-eprov gate=query
// Q06: entry-provenance catalog,occupancy-query,unknown,missing
// Q06: q06-eprov yes
// Q06: can-run-plan no
