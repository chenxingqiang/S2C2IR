// CUDA and Ascend CAP_SCHEMA_REGIME. Query only.
// Both tuples stay bandwidth, latency, occupancy, underdetermined.
// This lit test is not in check-host. No semantic cut. can-run-plan stays no.
// Do not FileCheck microseconds. This file does not require s2c2-opt.
// RUN: python3 %S/../../runtime/record_q52_careg.py --print-q52-careg | FileCheck %s --check-prefix=Q52 --implicit-check-not=can-run-plan=yes
// Q52: q52-careg gate=query
// Q52: cap-regime bandwidth
// Q52: cap-regime latency
// Q52: cap-regime occupancy
// Q52: cap-regime underdetermined
// Q52: q52-careg yes
// Q52: can-run-plan no
