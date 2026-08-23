// RUN: python3 %S/../../runtime/cuda/record_v3.py --print-ratio-schema | FileCheck %s
// RUN: python3 %S/../../runtime/cuda/record_v3.py --analyze-ratio %S/hidden-frac-ratio-fixture.csv | FileCheck %s --check-prefix=FIX
// RUN: python3 %S/../../runtime/cuda/record_v3.py --analyze-ratio %S/../../docs/design/v3-dataset/v3-matched-calibration.csv | FileCheck %s --check-prefix=CAL
// RUN: python3 %S/../../runtime/cuda/record_v3.py --print-calibration-schema | FileCheck %s --check-prefix=SCHEMA

// Ratio analysis protocol. Fixture locks flags; the frozen
// calibration CSV locks only the qualitative verdict, not a
// Cost number. Do not FileCheck a C_overlap rewrite.
module {
}

// CHECK: axis r=T_compute/T_copy
// CHECK: metric hidden_frac
// CHECK: outlier hidden_frac>1 measurement-noise
// CHECK: v3=not-claimed
// CHECK: cost=unchanged
// CHECK-NOT: Cost v0.4
// CHECK-NOT: password

// FIX: v3-ratio v3=not-claimed cost=unchanged
// FIX: measurement-noise
// FIX: f(r)=stable
// FIX: v3=not-claimed
// FIX-NOT: Cost v0.4

// CAL: outliers=2
// CAL: f(r)=not-stable
// CAL: v3=not-claimed
// CAL-NOT: Cost v0.4

// SCHEMA: score3 not-validated
// SCHEMA: v3=not-claimed
