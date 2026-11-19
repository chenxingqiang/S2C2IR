// Ascend measured-storage signatures. Read _SIG_S0 and _SIG_S1.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host.
// RUN: python3 %S/../../runtime/record_q82_sig.py --print-q82-sig | FileCheck %s --check-prefix=Q82 --implicit-check-not=can-run-plan=yes
// Q82: q82-sig gate=query
// Q82: sig-s0 MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER
// Q82: sig-s1 MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PRESERVE|TRANSFER
// Q82: q82-sig yes
// Q82: can-run-plan no
