// CUDA val-cc arms and dim from record_v3. Query only.
// No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Do not FileCheck microseconds.
// RUN: python3 %S/../../runtime/record_q71_vcc.py --print-q71-vcc | FileCheck %s --check-prefix=Q71 --implicit-check-not=can-run-plan=yes
// Q71: q71-vcc gate=query
// Q71: cc-arm val-cc-silu
// Q71: cc-arm val-cc-matmul
// Q71: cc-arm val-cc-seq
// Q71: cc-arm val-cc-ovl
// Q71: cc-arm val-cc-silu-silu
// Q71: cc-dim 1024
// Q71: q71-vcc yes
// Q71: can-run-plan no
