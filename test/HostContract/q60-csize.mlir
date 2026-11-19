// CUDA CAP_SIZE_BYTES from runtime/cuda/record_v3.py. Query only.
// The ladder stays 1024 through 268435456. No semantic cut.
// This lit test is not in check-host. can-run-plan stays no.
// Do not FileCheck microseconds. This file does not require s2c2-opt.
// RUN: python3 %S/../../runtime/record_q60_csize.py --print-q60-csize | FileCheck %s --check-prefix=Q60 --implicit-check-not=can-run-plan=yes
// Q60: q60-csize gate=query
// Q60: cap-size 1024
// Q60: cap-size 4096
// Q60: cap-size 16384
// Q60: cap-size 65536
// Q60: cap-size 1048576
// Q60: cap-size 4194304
// Q60: cap-size 16777216
// Q60: cap-size 67108864
// Q60: cap-size 268435456
// Q60: q60-csize yes
// Q60: can-run-plan no
