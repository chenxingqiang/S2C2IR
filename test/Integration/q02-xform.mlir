// TRANSFORMATION_V01 is keep-evict-transfer-restore on rewrite and apply.
// Query only. No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_q02_xform.py --print-q02-xform | FileCheck %s --check-prefix=Q02 --implicit-check-not=can-run-plan=yes
// Q02: q02-xform gate=query
// Q02: transformation keep-evict-transfer-restore
// Q02: q02-xform yes
// Q02: can-run-plan no
