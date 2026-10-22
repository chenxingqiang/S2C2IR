// Measured-capacity field names required by record_capacity.MEAS_CAP_FIELDS.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host.
// RUN: python3 %S/../../runtime/record_q30_capmeas.py --print-q30-capmeas | FileCheck %s --check-prefix=Q30 --implicit-check-not=can-run-plan=yes
// Q30: q30-capmeas gate=query
// Q30: meas-field schema
// Q30: meas-field profile
// Q30: meas-field workload_class
// Q30: meas-field candidate_identity
// Q30: meas-field measured_time_us
// Q30: meas-field repetitions
// Q30: meas-field correctness
// Q30: meas-field source
// Q30: meas-field measured
// Q30: meas-field note
// Q30: q30-capmeas yes
// Q30: can-run-plan no
