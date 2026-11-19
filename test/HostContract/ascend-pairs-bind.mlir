// Phase 3B Ascend pairs. Read PAIRS from record_ascend.
// Query only. No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_ascend_pairs_bind.py --print-ascend-pairs-bind | FileCheck %s --check-prefix=APB
// APB: ascend-pairs-bind gate=query
// APB: pair C||HtoD
// APB: pair C||C
// APB: pair HtoD||DtoH
// APB: ascend-pairs-bind yes
// APB: can-run-plan no
