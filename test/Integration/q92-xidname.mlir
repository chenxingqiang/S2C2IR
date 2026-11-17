// RUN: python3 %S/../../runtime/record_q92_xidname.py --print-q92-xidname | FileCheck %s --check-prefix=Q92 --implicit-check-not=can-run-plan=yes
// Q92: q92-xidname gate=query
// Q92: xid-case cuda-legal
// Q92: xid-case ascend-dma
// Q92: xid-case cpu-na
// Q92: xid-case cross-target
// Q92: q92-xidname yes
// Q92: can-run-plan no
