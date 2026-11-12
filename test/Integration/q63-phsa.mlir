// RUN: python3 %S/../../runtime/record_q63_phsa.py --print-q63-phsa | FileCheck %s --check-prefix=Q63 --implicit-check-not=can-run-plan=yes
// Q63: q63-phsa gate=query
// Q63: phase-arm phase-seq
// Q63: phase-arm phase-ovl
// Q63: phase-arm phase-copy
// Q63: phase-arm phase-compute
// Q63: q63-phsa yes
// Q63: can-run-plan no
