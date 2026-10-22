// Ascend hierarchy tails from runtime/ascend/record_ascend._HIER_TAILS.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Does not call run_analyzer.
// RUN: python3 %S/../../runtime/record_q83_htail.py --print-q83-htail | FileCheck %s --check-prefix=Q83 --implicit-check-not=can-run-plan=yes
// Q83: q83-htail gate=query
// Q83: hier-tail PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
// Q83: hier-tail PREFETCH|TRANSFER|KEEP_RESIDENCY|TRANSFER
// Q83: hier-tail PREFETCH|TRANSFER|TRANSFER|KEEP_RESIDENCY
// Q83: hier-tail PREFETCH|TRANSFER|TRANSFER|TRANSFER
// Q83: hier-tail PRESERVE|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
// Q83: hier-tail PRESERVE|TRANSFER|KEEP_RESIDENCY|TRANSFER
// Q83: hier-tail PRESERVE|TRANSFER|TRANSFER|KEEP_RESIDENCY
// Q83: hier-tail PRESERVE|TRANSFER|TRANSFER|TRANSFER
// Q83: q83-htail yes
// Q83: can-run-plan no
