// RUN: python3 %S/../../runtime/record_q95_ahpair.py --print-q95-ahpair | FileCheck %s --check-prefix=Q95 --implicit-check-not=can-run-plan=yes
// Q95: q95-ahpair gate=query
// Q95: ascend-pair R1 C||HtoD compute htod
// Q95: ascend-pair R2 C||C compute compute
// Q95: ascend-pair R3 HtoD||DtoH htod dtoh
// Q95: q95-ahpair yes
// Q95: can-run-plan no
