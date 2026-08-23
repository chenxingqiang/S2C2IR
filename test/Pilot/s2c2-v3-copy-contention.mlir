// RUN: s2c2-cuda-adapter --dry-run --contend 2>&1 | FileCheck %s
// RUN: s2c2-cuda-adapter --dry-run 2>&1 | FileCheck %s --check-prefix=ABC
// RUN: python3 %S/../../runtime/cuda/record_v3.py --print-schema | FileCheck %s --check-prefix=SCHEMA
// RUN: python3 %S/../../runtime/cuda/record_v3.py --print-contend-schema | FileCheck %s --check-prefix=CSCHEMA
// RUN: python3 %S/../../runtime/cuda/record_v3.py --analyze-contend %S/copy-contention-fixture.jsonl | FileCheck %s --check-prefix=AN

// Host + recorder protocol for two-HtoD contention. No device,
// no microseconds FileCheck of hardware, no Cost change.
module {
}

// CHECK: s2c2-cuda-adapter dry-run=1
// CHECK: s2c2-cuda-adapter contend=one remaining=1xHtoD
// CHECK: s2c2-cuda-adapter contend=seq remaining=2xHtoD
// CHECK: s2c2-cuda-adapter contend=par remaining=2xHtoD
// CHECK: s2c2-cuda-adapter contend=par-split remaining=2xHtoD
// CHECK: s2c2-cuda-adapter contend score3=not-applicable
// CHECK: s2c2-cuda-adapter contend cost=unchanged
// CHECK: s2c2-cuda-adapter v3=not-claimed
// CHECK-NOT: func=pilot_a
// CHECK-NOT: s2c2-search
// CHECK-NOT: password

// ABC: s2c2-cuda-adapter func=pilot_a_ssd_hbm_compute
// ABC: s2c2-cuda-adapter func=pilot_b_compute_par_comm
// ABC: s2c2-cuda-adapter func=pilot_c_pipeline_three_stage
// ABC-NOT: contend=par

// SCHEMA: score3
// SCHEMA: source cuda_runtime=cudaRuntimeGetVersion
// SCHEMA: v3=not-claimed

// CSCHEMA: contend-arm one seq par par-split
// CSCHEMA: remaining-work 2xHtoD
// CSCHEMA: score3 not-applicable
// CSCHEMA: source driver_version=nvidia-smi
// CSCHEMA: source nvcc_version=nvcc
// CSCHEMA: source cuda_runtime=cudaRuntimeGetVersion
// CSCHEMA: v3=not-claimed
// CSCHEMA: cost=unchanged

// AN: v3-contend v3=not-claimed cost=unchanged
// AN: serialize
// AN: mean_serialize_frac=1.000
// AN: v3=not-claimed
// AN-NOT: Cost v0.4
// AN-NOT: password
