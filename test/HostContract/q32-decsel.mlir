// Decision and sufficiency SELECTED_S0 and SELECTED_S1 must match.
// Query only. No predicate, device, dialect, backend, or semantic cut.
// can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_q32_decsel.py --print-q32-decsel | FileCheck %s --check-prefix=Q32 --implicit-check-not=can-run-plan=yes
// Q32: q32-decsel gate=query
// Q32: selected-s0 keep{0,1}|evict{2}|rematerialize{}
// Q32: selected-s1 keep{1,2}|evict{0}|rematerialize{}
// Q32: q32-decsel yes
// Q32: can-run-plan no
