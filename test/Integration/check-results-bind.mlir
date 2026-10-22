// Checking result set and the constraint-to-result map.
// Read RESULTS and _RESULT_FOR from the checking host.
// This lit test is not in check-host. No semantic cut. can-run-plan stays no.
// Do not FileCheck microseconds. This file does not require s2c2-opt.
// RUN: python3 %S/../../runtime/record_check_results_bind.py --print-check-results-bind | FileCheck %s --check-prefix=CRS --implicit-check-not=can-run-plan=yes

func.func @dummy() {
  return
}

// CRS: check-results-bind gate=query
// CRS: result satisfy
// CRS: result violate
// CRS: result unproven
// CRS: allowed-maps satisfy
// CRS: forbidden-maps violate
// CRS: not-applicable-maps violate
// CRS: unproven-maps unproven
// CRS: check-results-bind yes
// CRS: can-run-plan no
// CRS-NOT: can-run-plan=yes
