// Acceptance scenario id and device from record_apply_scenario.
// Query only. Does not call run_analyzer. No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_q46_scenid.py --print-q46-scenid | FileCheck %s --check-prefix=Q46 --implicit-check-not=can-run-plan=yes
// Q46: q46-scenid gate=query
// Q46: scenario-id w0-3-2-storage-capacity-001
// Q46: scenario-device D0
// Q46: q46-scenid yes
// Q46: can-run-plan no
