// Ascend n-tile tails from record_ascend._NTILE_TAILS. Query only.
// No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Do not FileCheck microseconds.
// RUN: python3 %S/../../runtime/record_q84_ntail.py --print-q84-ntail | FileCheck %s --check-prefix=Q84 --implicit-check-not=can-run-plan=yes
// Q84: q84-ntail gate=query
// Q84: ntile-tail PREFETCH|TRANSFER//PREFETCH|TRANSFER//TRANSFER|TRANSFER
// Q84: ntile-tail PREFETCH|TRANSFER//PRESERVE|TRANSFER//TRANSFER|TRANSFER
// Q84: ntile-tail PRESERVE|TRANSFER//PREFETCH|TRANSFER//TRANSFER|TRANSFER
// Q84: ntile-tail PRESERVE|TRANSFER//PRESERVE|TRANSFER//TRANSFER|TRANSFER
// Q84: q84-ntail yes
// Q84: can-run-plan no
