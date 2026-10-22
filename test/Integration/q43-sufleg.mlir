// Sufficiency schema stays distinct from the realization-legality schema.
// Query only. This lit test is not in check-host. Does not call run_analyzer.
// No semantic cut. can-run-plan stays no.
// RUN: python3 %S/../../runtime/record_q43_sufleg.py --print-q43-sufleg | FileCheck %s --check-prefix=Q43 --implicit-check-not=can-run-plan=yes --implicit-check-not='decision-subject sufficient'
// Q43: q43-sufleg gate=query
// Q43: sufficiency-schema s2c2.sufficiency.v1
// Q43: legality-schema s2c2.realization_legality.v1
// Q43: q43-sufleg yes
// Q43: can-run-plan no
