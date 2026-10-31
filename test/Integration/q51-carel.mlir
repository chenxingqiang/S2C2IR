// CUDA and Ascend CAP_SCHEMA_RELATION. Query only.
// Both tuples stay serial, parallel, mixed, underdetermined.
// This lit test is not in check-host. No semantic cut. can-run-plan stays no.
// Do not FileCheck microseconds. This file does not require s2c2-opt.
// RUN: python3 %S/../../runtime/record_q51_carel.py --print-q51-carel | FileCheck %s --check-prefix=Q51 --implicit-check-not=can-run-plan=yes
// Q51: q51-carel gate=query
// Q51: cap-relation serial
// Q51: cap-relation parallel
// Q51: cap-relation mixed
// Q51: cap-relation underdetermined
// Q51: q51-carel yes
// Q51: can-run-plan no
