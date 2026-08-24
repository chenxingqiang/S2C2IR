// RUN: s2c2-cuda-adapter --dry-run --cuda-val 2>&1 | FileCheck %s
// RUN: s2c2-cuda-adapter --dry-run 2>&1 | FileCheck %s --check-prefix=ABC
// RUN: s2c2-cuda-adapter --dry-run --pipe 2>&1 | FileCheck %s --check-prefix=PIPE
// RUN: python3 %S/../../runtime/cuda/record_v3.py --print-cuda-val-schema | FileCheck %s --check-prefix=SCHEMA
// RUN: python3 %S/../../runtime/cuda/record_v3.py --analyze-cuda-val %S/cuda-val-fixture.jsonl | FileCheck %s --check-prefix=AN
// RUN: python3 %S/../../runtime/cuda/record_v3.py --analyze-cuda-val %S/../../docs/design/v3-dataset/v3-cuda-val.jsonl | FileCheck %s --check-prefix=HW

// Host + recorder protocol for CUDA Validation V1.
// No device, no microseconds FileCheck, no Cost change.
module {
}

// CHECK: s2c2-cuda-adapter dry-run=1
// CHECK: s2c2-cuda-adapter cuda-val=v1
// CHECK: s2c2-cuda-adapter cuda-val map stor.materialize=cudaMalloc
// CHECK: s2c2-cuda-adapter cuda-val map stor.transfer=cudaMemcpyAsync
// CHECK: s2c2-cuda-adapter cuda-val map comm.copy=cudaMemcpyAsync
// CHECK: s2c2-cuda-adapter cuda-val map sched.wait=cudaStreamWaitEvent
// CHECK: s2c2-cuda-adapter cuda-val map sched.concurrent=named-nonblocking-streams
// CHECK: s2c2-cuda-adapter cuda-val cell stream-named
// CHECK: s2c2-cuda-adapter cuda-val cell stream-default
// CHECK: s2c2-cuda-adapter cuda-val cell extra-hb=legacy-default
// CHECK: s2c2-cuda-adapter cuda-val pair=C||HtoD
// CHECK: s2c2-cuda-adapter cuda-val acceptance=HB-subset
// CHECK: s2c2-cuda-adapter cuda-val cost=unchanged
// CHECK: s2c2-cuda-adapter cuda-val semantics=unchanged
// CHECK: s2c2-cuda-adapter v3=not-claimed
// CHECK-NOT: func=pilot_a
// CHECK-NOT: password

// ABC: s2c2-cuda-adapter func=pilot_a_ssd_hbm_compute
// ABC: s2c2-cuda-adapter func=pilot_b_compute_par_comm
// ABC: s2c2-cuda-adapter func=pilot_c_pipeline_three_stage
// ABC-NOT: cuda-val=v1
// ABC-NOT: pipe=d1

// PIPE: s2c2-cuda-adapter pipe tiles=8
// PIPE-NOT: cuda-val=v1

// SCHEMA: cuda-val v1
// SCHEMA: pair C||HtoD
// SCHEMA: stream named-nonblocking legacy-default
// SCHEMA: acceptance HB-subset
// SCHEMA: semantics unchanged
// SCHEMA: v3=not-claimed
// SCHEMA: cost=unchanged

// AN: v3-cuda-val v1 pair=C||HtoD acceptance=HB-subset
// AN: extra_hb
// AN: named
// AN: default
// AN: counterexample
// AN: extra-hb=legacy-default
// AN: semantics=unchanged
// AN: v3=not-claimed
// AN-NOT: Cost v0.4
// AN-NOT: password

// Qualitative 4090 surface only. Do not FileCheck microseconds.
// HW: v3-cuda-val v1 pair=C||HtoD acceptance=HB-subset
// HW: counterexample
// HW: extra-hb=legacy-default
// HW: counterexamples=3
// HW: semantics=unchanged
// HW: v3=not-claimed
// HW-NOT: Cost v0.4
// HW-NOT: password
