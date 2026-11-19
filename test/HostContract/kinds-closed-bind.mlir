// RUN: python3 %S/../../runtime/record_kinds_closed_bind.py --print-kinds-closed-bind | FileCheck %s --check-prefix=KND
// KND: kinds-closed-bind gate=query
// KND: kind concurrent-pair
// KND: kind named-nonblocking
// KND: kind staged-dma
// KND: kinds-closed-bind yes
// KND: can-run-plan no
