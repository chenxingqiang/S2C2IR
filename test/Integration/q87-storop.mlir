// RUN: python3 %S/../../runtime/record_q87_storop.py --print-q87-storop | FileCheck %s --check-prefix=Q87 --implicit-check-not=can-run-plan=yes
// Q87: q87-storop gate=query
// Q87: stor-op object
// Q87: stor-op materialize
// Q87: stor-op transfer
// Q87: stor-op alloc
// Q87: stor-op dealloc
// Q87: stor-op pack
// Q87: stor-op unpack
// Q87: q87-storop yes
// Q87: can-run-plan no
