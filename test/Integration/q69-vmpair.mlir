// RUN: python3 %S/../../runtime/record_q69_vmpair.py --print-q69-vmpair | FileCheck %s --check-prefix=Q69 --implicit-check-not=can-run-plan=yes
// Q69: q69-vmpair gate=query
// Q69: mem-pair C||HtoD
// Q69: mem-pair C||DtoH
// Q69: q69-vmpair yes
// Q69: can-run-plan no
