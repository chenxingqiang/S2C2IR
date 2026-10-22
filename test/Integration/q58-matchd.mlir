// RUN: python3 %S/../../runtime/record_q58_matchd.py --print-q58-matchd | FileCheck %s --check-prefix=Q58 --implicit-check-not=can-run-plan=yes
// Q58: q58-matchd gate=query
// Q58: matched-k 1
// Q58: matched-k 8
// Q58: matched-k 32
// Q58: matched-k 64
// Q58: matched-arm matched-seq
// Q58: matched-arm matched-ovl
// Q58: matched-arm matched-copy
// Q58: matched-arm matched-compute
// Q58: q58-matchd yes
// Q58: can-run-plan no
