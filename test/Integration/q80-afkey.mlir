// Ascend FORBIDDEN_KEYS vendor prefixes. Query only.
// No semantic cut. can-run-plan stays no.
// This lit test is not in check-host. Do not call run_analyzer.
// RUN: python3 %S/../../runtime/record_q80_afkey.py --print-q80-afkey | FileCheck %s --check-prefix=Q80 --implicit-check-not=can-run-plan=yes --implicit-check-not=password
// Q80: q80-afkey gate=query
// Q80: forbidden-prefix acl_
// Q80: forbidden-prefix davinci_
// Q80: forbidden-prefix cube_
// Q80: forbidden-prefix vectorcore_
// Q80: forbidden-key-count 6
// Q80: has-localhost yes
// Q80: q80-afkey yes
// Q80: can-run-plan no
