// CUDA and Ascend CAP_SCHEMA_CONSTRAINT. Query only.
// Both tuples stay none, legacy_default, resource_contention,
// allocator_sync, copy_engine_contention.
// This lit test is not in check-host. No semantic cut. can-run-plan stays no.
// Do not FileCheck microseconds. This file does not require s2c2-opt.
// RUN: python3 %S/../../runtime/record_q53_cacst.py --print-q53-cacst | FileCheck %s --check-prefix=Q53 --implicit-check-not=can-run-plan=yes
// Q53: q53-cacst gate=query
// Q53: cap-constraint none
// Q53: cap-constraint legacy_default
// Q53: cap-constraint resource_contention
// Q53: cap-constraint allocator_sync
// Q53: cap-constraint copy_engine_contention
// Q53: q53-cacst yes
// Q53: can-run-plan no
