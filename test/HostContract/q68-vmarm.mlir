// RUN: python3 %S/../../runtime/record_q68_vmarm.py --print-q68-vmarm | FileCheck %s --check-prefix=Q68 --implicit-check-not=can-run-plan=yes
// Q68: q68-vmarm gate=query
// Q68: mem-arm val-htod-pinned
// Q68: mem-arm val-htod-pageable
// Q68: mem-arm val-dtoh-pinned
// Q68: mem-arm val-dtoh-pageable
// Q68: mem-arm val-compute-mem
// Q68: mem-arm val-ovl-htod-pin
// Q68: mem-arm val-ovl-htod-page
// Q68: mem-arm val-ovl-dtoh-pin
// Q68: mem-arm val-ovl-dtoh-page
// Q68: q68-vmarm yes
// Q68: can-run-plan no
