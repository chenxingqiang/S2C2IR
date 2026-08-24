// RUN: s2c2-cuda-adapter --dry-run --cuda-val-cc 2>&1 | FileCheck %s
// RUN: s2c2-cuda-adapter --dry-run --cuda-val-mem 2>&1 | FileCheck %s --check-prefix=V2
// RUN: s2c2-cuda-adapter --dry-run --cuda-val 2>&1 | FileCheck %s --check-prefix=V1
// RUN: s2c2-cuda-adapter --dry-run 2>&1 | FileCheck %s --check-prefix=ABC
// RUN: s2c2-cuda-adapter --dry-run --pipe 2>&1 | FileCheck %s --check-prefix=PIPE
// RUN: python3 %S/../../runtime/cuda/record_v3.py --print-cuda-val-cc-schema | FileCheck %s --check-prefix=SCHEMA
// RUN: python3 %S/../../runtime/cuda/record_v3.py --analyze-cuda-val-cc %S/cuda-val-cc-fixture.jsonl | FileCheck %s --check-prefix=AN
// RUN: python3 %S/../../runtime/cuda/record_v3.py --analyze-cuda-val-cc %S/../../docs/design/v3-dataset/v3-cuda-clight.jsonl | FileCheck %s --check-prefix=HW

// Host + recorder protocol for C_light || C_heavy (SiLU || GEMM).
// No device, no microseconds FileCheck, no Cost change.
module {
}

// CHECK: s2c2-cuda-adapter dry-run=1
// CHECK: s2c2-cuda-adapter cuda-val-cc=p0
// CHECK: s2c2-cuda-adapter cuda-val-cc map C_light=kxSiLU
// CHECK: s2c2-cuda-adapter cuda-val-cc map C_heavy=mxGEMM
// CHECK: s2c2-cuda-adapter cuda-val-cc map dim=1024
// CHECK: s2c2-cuda-adapter cuda-val-cc map sched.concurrent=named-nonblocking-streams
// CHECK: s2c2-cuda-adapter cuda-val-cc cell same-kind=SiLU||SiLU
// CHECK: s2c2-cuda-adapter cuda-val-cc cell mixed-kind=SiLU||GEMM
// CHECK: s2c2-cuda-adapter cuda-val-cc cell extra-hb=mixed-kind-serial
// CHECK: s2c2-cuda-adapter cuda-val-cc pair=C_light||C_heavy
// CHECK: s2c2-cuda-adapter cuda-val-cc acceptance=compute-resource
// CHECK: s2c2-cuda-adapter cuda-val-cc cost=unchanged
// CHECK: s2c2-cuda-adapter cuda-val-cc semantics=unchanged
// CHECK: s2c2-cuda-adapter v3=not-claimed
// CHECK-NOT: cuda-val-mem=v2
// CHECK-NOT: cuda-val=v1
// CHECK-NOT: password
// CHECK-NOT: Cost v0.4

// V2: s2c2-cuda-adapter cuda-val-mem=v2
// V2-NOT: cuda-val-cc=p0

// V1: s2c2-cuda-adapter cuda-val=v1
// V1-NOT: cuda-val-cc=p0

// ABC: s2c2-cuda-adapter func=pilot_a_ssd_hbm_compute
// ABC: s2c2-cuda-adapter func=pilot_b_compute_par_comm
// ABC: s2c2-cuda-adapter func=pilot_c_pipeline_three_stage
// ABC-NOT: cuda-val-cc=p0
// ABC-NOT: cuda-val-mem=v2
// ABC-NOT: cuda-val=v1

// PIPE: s2c2-cuda-adapter pipe tiles=8
// PIPE-NOT: cuda-val-cc=p0

// SCHEMA: cuda-val-cc p0
// SCHEMA: pair C_light||C_heavy
// SCHEMA: dim 1024
// SCHEMA: acceptance compute-resource
// SCHEMA: extra-hb none|mixed-kind-serial
// SCHEMA: semantics unchanged
// SCHEMA: v3=not-claimed
// SCHEMA: cost=unchanged

// AN: v3-cuda-val-cc p0 pair=C_light||C_heavy acceptance=compute-resource
// AN: extra_hb
// AN: mixed-kind-serial
// AN: kind-specific
// AN: control
// AN: mixed-kind-serial=1
// AN: kind-specific=2
// AN: still-serial=1
// AN: unexpected-same-kind=0
// AN: semantics=unchanged
// AN: v3=not-claimed
// AN-NOT: Cost v0.4
// AN-NOT: password

// Qualitative 4090 surface only. Do not FileCheck microseconds.
// HW: v3-cuda-val-cc p0 pair=C_light||C_heavy acceptance=compute-resource
// HW: mixed-kind-serial
// HW: still-serial
// HW: mixed-kind-serial=3
// HW: kind-specific=0
// HW: unexpected-same-kind=0
// HW: semantics=unchanged
// HW: v3=not-claimed
// HW-NOT: Cost v0.4
// HW-NOT: password
