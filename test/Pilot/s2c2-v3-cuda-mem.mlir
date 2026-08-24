// RUN: s2c2-cuda-adapter --dry-run --cuda-val-mem 2>&1 | FileCheck %s
// RUN: s2c2-cuda-adapter --dry-run --cuda-val 2>&1 | FileCheck %s --check-prefix=V1
// RUN: s2c2-cuda-adapter --dry-run 2>&1 | FileCheck %s --check-prefix=ABC
// RUN: s2c2-cuda-adapter --dry-run --pipe 2>&1 | FileCheck %s --check-prefix=PIPE
// RUN: python3 %S/../../runtime/cuda/record_v3.py --print-cuda-val-mem-schema | FileCheck %s --check-prefix=SCHEMA
// RUN: python3 %S/../../runtime/cuda/record_v3.py --analyze-cuda-val-mem %S/cuda-val-mem-fixture.jsonl | FileCheck %s --check-prefix=AN

// Host + recorder protocol for CUDA Validation V2 pinned vs pageable.
// No device, no microseconds FileCheck, no Cost change.
module {
}

// CHECK: s2c2-cuda-adapter dry-run=1
// CHECK: s2c2-cuda-adapter cuda-val-mem=v2
// CHECK: s2c2-cuda-adapter cuda-val-mem map stor.host=pinned|pageable
// CHECK: s2c2-cuda-adapter cuda-val-mem map stor.pinned=cudaHostAlloc
// CHECK: s2c2-cuda-adapter cuda-val-mem map stor.pageable=malloc
// CHECK: s2c2-cuda-adapter cuda-val-mem map comm.copy=cudaMemcpyAsync
// CHECK: s2c2-cuda-adapter cuda-val-mem map sched.concurrent=named-nonblocking-streams
// CHECK: s2c2-cuda-adapter cuda-val-mem cell host-pinned
// CHECK: s2c2-cuda-adapter cuda-val-mem cell host-pageable
// CHECK: s2c2-cuda-adapter cuda-val-mem cell extra-hb=pageable-host
// CHECK: s2c2-cuda-adapter cuda-val-mem pair=C||HtoD
// CHECK: s2c2-cuda-adapter cuda-val-mem pair=C||DtoH
// CHECK: s2c2-cuda-adapter cuda-val-mem acceptance=storage-comm
// CHECK: s2c2-cuda-adapter cuda-val-mem cost=unchanged
// CHECK: s2c2-cuda-adapter cuda-val-mem semantics=unchanged
// CHECK: s2c2-cuda-adapter v3=not-claimed
// CHECK-NOT: cuda-val=v1
// CHECK-NOT: func=pilot_a
// CHECK-NOT: password

// V1: s2c2-cuda-adapter cuda-val=v1
// V1-NOT: cuda-val-mem=v2

// ABC: s2c2-cuda-adapter func=pilot_a_ssd_hbm_compute
// ABC: s2c2-cuda-adapter func=pilot_b_compute_par_comm
// ABC: s2c2-cuda-adapter func=pilot_c_pipeline_three_stage
// ABC-NOT: cuda-val-mem=v2
// ABC-NOT: cuda-val=v1

// PIPE: s2c2-cuda-adapter pipe tiles=8
// PIPE-NOT: cuda-val-mem=v2

// SCHEMA: cuda-val-mem v2
// SCHEMA: pair C||HtoD C||DtoH
// SCHEMA: host pinned pageable
// SCHEMA: acceptance storage-comm
// SCHEMA: semantics unchanged
// SCHEMA: v3=not-claimed
// SCHEMA: cost=unchanged

// AN: v3-cuda-val-mem v2 pair=C||HtoD,C||DtoH acceptance=storage-comm
// AN: extra_hb
// AN: pinned
// AN: pageable
// AN: counterexample
// AN: extra-hb=pageable-host
// AN: counterexamples=6
// AN: semantics=unchanged
// AN: v3=not-claimed
// AN-NOT: Cost v0.4
// AN-NOT: password
