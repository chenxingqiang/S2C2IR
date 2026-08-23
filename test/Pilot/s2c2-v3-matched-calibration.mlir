// RUN: python3 %S/../../runtime/cuda/record_v3.py --print-calibration-schema | FileCheck %s
// RUN: python3 %S/../../runtime/cuda/record_v3.py --calibrate %S/matched-overlap-fixture.jsonl | FileCheck %s --check-prefix=CAL
// RUN: python3 %S/../../runtime/cuda/record_v3.py --print-schema | FileCheck %s --check-prefix=META

// Freeze witness for the matched calibration map. No hardware
// microseconds FileCheck. Cost stays unchanged.
module {
}

// CHECK: N,k,T_seq_us,T_ovl_us,T_copy_us,T_compute_us,ratio,gain_us,ideal_us,hidden_frac,seq_over_sum,ovl_over_max
// CHECK: map (N,k)->(T_copy,T_compute,T_seq,T_ovl,hidden_frac)
// CHECK: overlap-semantics direction-validated
// CHECK: score3 not-validated
// CHECK: v3=not-claimed
// CHECK: cost=unchanged
// CHECK-NOT: Cost v0.4
// CHECK-NOT: password

// CAL: v3-calibration v3=not-claimed cost=unchanged
// CAL: hidden_frac
// CAL: overlap-semantics=direction-validated
// CAL: score3=not-validated
// CAL: v3=not-claimed
// CAL-NOT: Cost v0.4

// META: source cuda_runtime=cudaRuntimeGetVersion
// META: v3=not-claimed
