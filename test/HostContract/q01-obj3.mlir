// OBJECT_3 is the string 3 on authorization, rewrite, and apply.
// Query only. No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_q01_obj3.py --print-q01-obj3 | FileCheck %s --check-prefix=Q01 --implicit-check-not=can-run-plan=yes
// Q01: q01-obj3 gate=query
// Q01: object-3 3
// Q01: q01-obj3 yes
// Q01: can-run-plan no
