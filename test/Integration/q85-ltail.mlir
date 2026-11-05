// Ascend loop tails from runtime/ascend/record_ascend._LOOP_TAILS.
// Query only. No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Does not call run_analyzer.
// RUN: python3 %S/../../runtime/record_q85_ltail.py --print-q85-ltail | FileCheck %s --check-prefix=Q85 --implicit-check-not=can-run-plan=yes
// Q85: q85-ltail gate=query
// Q85: loop-tail PREFETCH//TRANSFER//TRANSFER|KEEP_RESIDENCY|TRANSFER//MATERIALIZE
// Q85: loop-tail PREFETCH//TRANSFER//TRANSFER|TRANSFER|TRANSFER//MATERIALIZE
// Q85: loop-tail PRESERVE//TRANSFER//TRANSFER|KEEP_RESIDENCY|TRANSFER//MATERIALIZE
// Q85: loop-tail PRESERVE//TRANSFER//TRANSFER|TRANSFER|TRANSFER//MATERIALIZE
// Q85: q85-ltail yes
// Q85: can-run-plan no
