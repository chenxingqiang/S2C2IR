// v0.1 rewrite sequence shared by rewrite and apply.
// No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_sequence_v01_bind.py --print-sequence-v01-bind | FileCheck %s --check-prefix=SEQ
// SEQ: sequence-v01-bind gate=query
// SEQ: sequence KEEP,EVICT,TRANSFER,RESTORE
// SEQ: sequence-v01-bind yes
// SEQ: can-run-plan no
