// RUN: s2c2-cuda-adapter --dry-run --pipe-tiles 2>&1 | FileCheck %s
// RUN: s2c2-cuda-adapter --dry-run 2>&1 | FileCheck %s --check-prefix=ABC
// RUN: s2c2-cuda-adapter --dry-run --pipe 2>&1 | FileCheck %s --check-prefix=PIPE8
// RUN: python3 %S/../../runtime/cuda/record_v3.py --print-pipe-tiles-schema | FileCheck %s --check-prefix=SCHEMA
// RUN: python3 %S/../../runtime/cuda/record_v3.py --analyze-pipe-tiles %S/pipe-tiles-fixture.jsonl | FileCheck %s --check-prefix=AN
// RUN: python3 %S/../../runtime/cuda/record_v3.py --analyze-pipe %S/pipe-tiles-fixture.jsonl | FileCheck %s --check-prefix=ISO
// RUN: python3 %S/../../runtime/cuda/record_v3.py --analyze-pipe %S/pipe-depth-fixture.jsonl | FileCheck %s --check-prefix=OLD
// RUN: python3 %S/../../runtime/cuda/record_v3.py --analyze-pipe-tiles %S/../../docs/design/v3-dataset/v3-pipe-tiles.jsonl | FileCheck %s --check-prefix=HW

// Host + recorder protocol for C||HtoD tiles sanity.
// No device, no microseconds FileCheck, no Cost change.
module {
}

// CHECK: s2c2-cuda-adapter dry-run=1
// CHECK: s2c2-cuda-adapter pipe-tiles=4 remaining=C||HtoD
// CHECK: s2c2-cuda-adapter pipe-tiles=8 remaining=C||HtoD
// CHECK: s2c2-cuda-adapter pipe-tiles=16 remaining=C||HtoD
// CHECK: s2c2-cuda-adapter pipe-tiles=32 remaining=C||HtoD
// CHECK: s2c2-cuda-adapter pipe-tiles pair=C||HtoD
// CHECK: s2c2-cuda-adapter pipe-tiles depths=1,2,3,4
// CHECK: s2c2-cuda-adapter pipe-tiles set=4,8,16,32
// CHECK: s2c2-cuda-adapter pipe-tiles score3=not-applicable
// CHECK: s2c2-cuda-adapter pipe-tiles cost=unchanged
// CHECK: s2c2-cuda-adapter v3=not-claimed
// CHECK-NOT: remaining=8tile-seq
// CHECK-NOT: func=pilot_a
// CHECK-NOT: s2c2-search
// CHECK-NOT: password

// ABC: s2c2-cuda-adapter func=pilot_a_ssd_hbm_compute
// ABC: s2c2-cuda-adapter func=pilot_b_compute_par_comm
// ABC: s2c2-cuda-adapter func=pilot_c_pipeline_three_stage
// ABC-NOT: pipe-tiles=4
// ABC-NOT: pipe=d1

// PIPE8: s2c2-cuda-adapter pipe=d1 remaining=8tile-seq
// PIPE8: s2c2-cuda-adapter pipe tiles=8
// PIPE8-NOT: pipe-tiles=4
// PIPE8-NOT: pipe-tiles set=

// SCHEMA: pipe-tiles-arm t4 t8 t16 t32
// SCHEMA: pair C||HtoD
// SCHEMA: tiles 4 8 16 32
// SCHEMA: v3=not-claimed
// SCHEMA: cost=unchanged

// AN: v3-pipe-tiles v3=not-claimed cost=unchanged pair=C||HtoD tiles=4,8,16,32
// AN: sp2
// AN: sat
// AN: slices=4
// AN: v3=not-claimed
// AN: by-tiles tiles=4
// AN: by-tiles tiles=32
// AN-NOT: Cost v0.4
// AN-NOT: password

// ISO: v3-pipe v3=not-claimed cost=unchanged pair=C||HtoD tiles=8
// ISO-NOT: Cost v0.4

// OLD: v3-pipe v3=not-claimed cost=unchanged pair=C||HtoD tiles=8
// OLD: sat
// OLD: v3=not-claimed

// Qualitative 4090 surface only. Do not FileCheck microseconds.
// HW: v3-pipe-tiles v3=not-claimed cost=unchanged pair=C||HtoD tiles=4,8,16,32
// HW: sat
// HW: slices=12
// HW: mean_sat_d4/d2
// HW: v3=not-claimed
// HW: by-tiles tiles=4
// HW: by-tiles tiles=32
// HW-NOT: Cost v0.4
// HW-NOT: password
