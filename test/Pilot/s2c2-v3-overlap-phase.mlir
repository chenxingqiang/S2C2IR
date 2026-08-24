// RUN: s2c2-cuda-adapter --dry-run --phase 2>&1 | FileCheck %s
// RUN: s2c2-cuda-adapter --dry-run 2>&1 | FileCheck %s --check-prefix=ABC
// RUN: python3 %S/../../runtime/cuda/record_v3.py --print-phase-schema | FileCheck %s --check-prefix=SCHEMA
// RUN: python3 %S/../../runtime/cuda/record_v3.py --analyze-phase %S/overlap-phase-fixture.jsonl | FileCheck %s --check-prefix=AN

// Host + recorder protocol for the C||HtoD overlap phase
// diagram. No device, no microseconds FileCheck, no Cost change.
module {
}

// CHECK: s2c2-cuda-adapter dry-run=1
// CHECK: s2c2-cuda-adapter phase=seq remaining=1xHtoD+kxSiLU
// CHECK: s2c2-cuda-adapter phase=ovl remaining=1xHtoD+kxSiLU
// CHECK: s2c2-cuda-adapter phase axis=r=T_compute/T_copy
// CHECK: s2c2-cuda-adapter phase axis=size=N
// CHECK: s2c2-cuda-adapter phase pair=C||HtoD
// CHECK: s2c2-cuda-adapter phase score3=not-applicable
// CHECK: s2c2-cuda-adapter phase cost=unchanged
// CHECK: s2c2-cuda-adapter v3=not-claimed
// CHECK-NOT: func=pilot_a
// CHECK-NOT: s2c2-search
// CHECK-NOT: password

// ABC: s2c2-cuda-adapter func=pilot_a_ssd_hbm_compute
// ABC: s2c2-cuda-adapter func=pilot_b_compute_par_comm
// ABC: s2c2-cuda-adapter func=pilot_c_pipeline_three_stage
// ABC-NOT: phase=seq

// SCHEMA: phase-arm seq ovl copy compute
// SCHEMA: axis r=T_compute/T_copy
// SCHEMA: axis size=N
// SCHEMA: pair C||HtoD
// SCHEMA: v3=not-claimed
// SCHEMA: cost=unchanged

// AN: v3-phase v3=not-claimed cost=unchanged pair=C||HtoD
// AN: copy-dominated
// AN: underdetermined
// AN: balanced
// AN: parallel
// AN: compute-dominated
// AN: v3=not-claimed
// AN-NOT: Cost v0.4
// AN-NOT: password
