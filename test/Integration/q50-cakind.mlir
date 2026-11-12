// RUN: python3 %S/../../runtime/record_q50_cakind.py --print-q50-cakind | FileCheck %s --check-prefix=Q50 --implicit-check-not=can-run-plan=yes
// Q50: q50-cakind gate=query
// Q50: cap-kind pair
// Q50: cap-kind depth
// Q50: cap-kind memory
// Q50: cap-kind sync
// Q50: q50-cakind yes
// Q50: can-run-plan no
