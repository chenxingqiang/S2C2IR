// RUN: python3 %S/../../runtime/record_q66_varm.py --print-q66-varm | FileCheck %s --check-prefix=Q66 --implicit-check-not=can-run-plan=yes
// Q66: q66-varm gate=query
// Q66: val-arm val-copy-named
// Q66: val-arm val-compute-named
// Q66: val-arm val-seq-named
// Q66: val-arm val-ovl-named
// Q66: val-arm val-copy-default
// Q66: val-arm val-compute-default
// Q66: val-arm val-seq-default
// Q66: val-arm val-ovl-default
// Q66: q66-varm yes
// Q66: can-run-plan no
