// RUN: s2c2-cuda-adapter --dry-run --cap 2>&1 | FileCheck %s
// RUN: s2c2-cuda-adapter --dry-run 2>&1 | FileCheck %s --check-prefix=ABC
// RUN: python3 %S/../../runtime/cuda/record_v3.py --print-cap-schema | FileCheck %s --check-prefix=SCHEMA
// RUN: python3 %S/../../runtime/cuda/record_v3.py --analyze-cap %S/capability-matrix-fixture.jsonl | FileCheck %s --check-prefix=AN
// RUN: python3 %S/../../runtime/cuda/record_v3.py --analyze-cap %S/../../docs/design/v3-dataset/v3-cap.jsonl | FileCheck %s --check-prefix=HW

// Host + recorder protocol for the 4090 capability matrix. No
// device, no microseconds FileCheck of hardware, no Cost change.
module {
}

// CHECK: s2c2-cuda-adapter dry-run=1
// CHECK: s2c2-cuda-adapter cap=htod remaining=1xHtoD
// CHECK: s2c2-cuda-adapter cap=dtoh remaining=1xDtoH
// CHECK: s2c2-cuda-adapter cap=htod-dtoh-par remaining=HtoD||DtoH
// CHECK: s2c2-cuda-adapter cap=compute-htod remaining=kxSiLU||HtoD
// CHECK: s2c2-cuda-adapter cap=event-sync remaining=event
// CHECK: s2c2-cuda-adapter cap=matmul remaining=tiled-gemm
// CHECK: s2c2-cuda-adapter cap score3=not-applicable
// CHECK: s2c2-cuda-adapter cap cost=unchanged
// CHECK: s2c2-cuda-adapter v3=not-claimed
// CHECK-NOT: func=pilot_a
// CHECK-NOT: s2c2-search
// CHECK-NOT: password

// ABC: s2c2-cuda-adapter func=pilot_a_ssd_hbm_compute
// ABC: s2c2-cuda-adapter func=pilot_b_compute_par_comm
// ABC: s2c2-cuda-adapter func=pilot_c_pipeline_three_stage
// ABC-NOT: cap=htod

// SCHEMA: cap-arm pairs sync size intensity
// SCHEMA: score3 not-applicable
// SCHEMA: source cuda_runtime=cudaRuntimeGetVersion
// SCHEMA: v3=not-claimed
// SCHEMA: cost=unchanged

// AN: v3-cap v3=not-claimed cost=unchanged
// AN: HtoD||DtoH
// AN: parallel
// AN: HtoD||HtoD
// AN: serial
// AN: C||HtoD
// AN: T_launch
// AN: cap-event-sync
// AN: intensity
// AN: v3=not-claimed
// AN-NOT: Cost v0.4
// AN-NOT: password

// Qualitative 4090 matrix only. Do not FileCheck microseconds.
// HW: v3-cap v3=not-claimed cost=unchanged
// HW: HtoD||DtoH
// HW: mixed
// HW: HtoD||HtoD
// HW: serial
// HW: C||HtoD
// HW: parallel
// HW: T_launch
// HW: v3=not-claimed
// HW-NOT: Cost v0.4
// HW-NOT: password
