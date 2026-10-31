// CUDA pair arms from record_v3.CAP_PAIR_ARMS. Query only.
// No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Do not FileCheck microseconds.
// RUN: python3 %S/../../runtime/record_q79_cparm.py --print-q79-cparm | FileCheck %s --check-prefix=Q79 --implicit-check-not=can-run-plan=yes
// Q79: q79-cparm gate=query
// Q79: pair-arm cap-htod
// Q79: pair-arm cap-dtoh
// Q79: pair-arm cap-htod-dtoh-seq
// Q79: pair-arm cap-htod-dtoh-event
// Q79: pair-arm cap-htod-dtoh-par
// Q79: pair-arm cap-htod-htod-par
// Q79: pair-arm cap-dtoh-dtoh-par
// Q79: pair-arm cap-compute
// Q79: pair-arm cap-compute-htod
// Q79: pair-arm cap-compute-dtoh
// Q79: pair-arm cap-compute-compute
// Q79: q79-cparm yes
// Q79: can-run-plan no
