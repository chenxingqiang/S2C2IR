// SEQUENCE_SUBJECT stays rewrite-sequence.
// Query only. No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_q03_seqsub.py --print-q03-seqsub | FileCheck %s --check-prefix=Q03 --implicit-check-not=can-run-plan=yes
// Q03: q03-seqsub gate=query
// Q03: sequence-subject rewrite-sequence
// Q03: q03-seqsub yes
// Q03: can-run-plan no
