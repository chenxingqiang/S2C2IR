// CUDA cap pairs from record_v3.CAP_PAIRS. Query only.
// No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Do not FileCheck microseconds.
// RUN: python3 %S/../../runtime/record_q78_cpair.py --print-q78-cpair | FileCheck %s --check-prefix=Q78 --implicit-check-not=can-run-plan=yes
// Q78: q78-cpair gate=query
// Q78: cap-pair HtoD||DtoH
// Q78: cap-pair HtoD||HtoD
// Q78: cap-pair DtoH||DtoH
// Q78: cap-pair C||HtoD
// Q78: cap-pair C||DtoH
// Q78: cap-pair C||C
// Q78: q78-cpair yes
// Q78: can-run-plan no
