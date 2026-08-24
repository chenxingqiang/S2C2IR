// RUN: s2c2-cuda-adapter --dry-run --pipe 2>&1 | FileCheck %s
// RUN: s2c2-cuda-adapter --dry-run 2>&1 | FileCheck %s --check-prefix=ABC
// RUN: python3 %S/../../runtime/cuda/record_v3.py --print-pipe-schema | FileCheck %s --check-prefix=SCHEMA
// RUN: python3 %S/../../runtime/cuda/record_v3.py --analyze-pipe %S/pipe-depth-fixture.jsonl | FileCheck %s --check-prefix=AN

// Host + recorder protocol for C||HtoD pipeline depth.
// No device, no microseconds FileCheck, no Cost change.
module {
}

// CHECK: s2c2-cuda-adapter dry-run=1
// CHECK: s2c2-cuda-adapter pipe=d1 remaining=8tile-seq
// CHECK: s2c2-cuda-adapter pipe=d2 remaining=8tile-double
// CHECK: s2c2-cuda-adapter pipe pair=C||HtoD
// CHECK: s2c2-cuda-adapter pipe tiles=8
// CHECK: s2c2-cuda-adapter pipe score3=not-applicable
// CHECK: s2c2-cuda-adapter pipe cost=unchanged
// CHECK: s2c2-cuda-adapter v3=not-claimed
// CHECK-NOT: func=pilot_a
// CHECK-NOT: s2c2-search
// CHECK-NOT: password

// ABC: s2c2-cuda-adapter func=pilot_a_ssd_hbm_compute
// ABC: s2c2-cuda-adapter func=pilot_b_compute_par_comm
// ABC: s2c2-cuda-adapter func=pilot_c_pipeline_three_stage
// ABC-NOT: pipe=d1

// SCHEMA: pipe-arm d1 d2 d3 d4 copy compute
// SCHEMA: pair C||HtoD
// SCHEMA: tiles 8
// SCHEMA: v3=not-claimed
// SCHEMA: cost=unchanged

// AN: v3-pipe v3=not-claimed cost=unchanged pair=C||HtoD tiles=8
// AN: sp2
// AN: sat
// AN: v3=not-claimed
// AN-NOT: Cost v0.4
// AN-NOT: password
