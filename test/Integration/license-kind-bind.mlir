// LICENSE_KIND_V01 is storage-capacity-rewrite on auth, rew, and apply.
// Query only. No semantic cut. can-run-plan stays no.
// Do not print rewrite-license=yes.
// RUN: python3 %S/../../runtime/record_license_kind_bind.py --print-license-kind-bind | FileCheck %s --check-prefix=LKB --implicit-check-not=rewrite-license=yes
// LKB: license-kind-bind gate=query
// LKB: license-kind storage-capacity-rewrite
// LKB: license-kind-bind yes
// LKB: can-run-plan no
