// RUN: s2c2-cuda-adapter --dry-run --matched 2>&1 | FileCheck %s
// RUN: s2c2-cuda-adapter --dry-run 2>&1 | FileCheck %s --check-prefix=ABC
// RUN: python3 %S/../../runtime/cuda/record_v3.py --print-schema | FileCheck %s --check-prefix=SCHEMA
// RUN: python3 %S/../../runtime/cuda/record_v3.py --print-matched-schema | FileCheck %s --check-prefix=MSCHEMA
// RUN: python3 %S/../../runtime/cuda/record_v3.py --analyze-matched %S/matched-overlap-fixture.jsonl | FileCheck %s --check-prefix=AN

// Host + recorder protocol for matched-workload overlap. No device,
// no microseconds FileCheck of hardware, no Cost change.
module {
}

// CHECK: s2c2-cuda-adapter dry-run=1
// CHECK: s2c2-cuda-adapter matched=seq remaining=1xHtoD+kxSiLU
// CHECK: s2c2-cuda-adapter matched=ovl remaining=1xHtoD+kxSiLU
// CHECK: s2c2-cuda-adapter matched=copy remaining=1xHtoD
// CHECK: s2c2-cuda-adapter matched=compute remaining=kxSiLU
// CHECK: s2c2-cuda-adapter matched score3=not-applicable
// CHECK: s2c2-cuda-adapter matched cost=unchanged
// CHECK: s2c2-cuda-adapter v3=not-claimed
// CHECK-NOT: func=pilot_a
// CHECK-NOT: s2c2-search
// CHECK-NOT: password

// ABC: s2c2-cuda-adapter func=pilot_a_ssd_hbm_compute
// ABC: s2c2-cuda-adapter func=pilot_b_compute_par_comm
// ABC: s2c2-cuda-adapter func=pilot_c_pipeline_three_stage
// ABC-NOT: matched=seq

// SCHEMA: score3
// SCHEMA: source cuda_runtime=cudaRuntimeGetVersion
// SCHEMA: v3=not-claimed

// MSCHEMA: matched-arm seq ovl copy compute
// MSCHEMA: remaining-work 1xHtoD+kxSiLU
// MSCHEMA: score3 not-applicable
// MSCHEMA: source driver_version=nvidia-smi
// MSCHEMA: source nvcc_version=nvcc
// MSCHEMA: source cuda_runtime=cudaRuntimeGetVersion
// MSCHEMA: v3=not-claimed
// MSCHEMA: cost=unchanged

// AN: v3-matched v3=not-claimed cost=unchanged
// AN: hidden
// AN: mean_hidden_frac=0.909
// AN: v3=not-claimed
// AN-NOT: Cost v0.4
// AN-NOT: password
