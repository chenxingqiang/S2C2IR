// RUN: python3 %S/../../runtime/record_q45_occobj.py --print-q45-occobj | FileCheck %s --check-prefix=Q45 --implicit-check-not=can-run-plan=yes
// Q45: q45-occobj gate=query
// Q45: object-canonical 2
// Q45: q45-occobj yes
// Q45: can-run-plan no
