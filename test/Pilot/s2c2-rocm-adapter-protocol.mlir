// RUN: s2c2-rocm-adapter --dry-run 2>&1 | FileCheck %s
// RUN: s2c2-rocm-adapter --dry-run --pairs 2>&1 | FileCheck %s --check-prefix=PAIRS
// RUN: s2c2-rocm-adapter --dry-run --workload 2>&1 | FileCheck %s --check-prefix=WL
// RUN: s2c2-rocm-adapter --dry-run --classify=10:10:10 2>&1 | FileCheck %s --check-prefix=PAR
// RUN: s2c2-rocm-adapter --dry-run --classify=10:10:19.5 2>&1 | FileCheck %s --check-prefix=SER
// RUN: s2c2-rocm-adapter --dry-run --classify=10:10:16 2>&1 | FileCheck %s --check-prefix=MIX
// RUN: s2c2-rocm-adapter --dry-run --emit-record='C||C' 2>&1 | FileCheck %s --check-prefix=EMIT
// RUN: not s2c2-rocm-adapter --dry-run --accept-hardware=sm89:rtx4090 2>&1 | FileCheck %s --check-prefix=FOR
// RUN: s2c2-rocm-adapter --dry-run --accept-hardware=gfx1100:amd 2>&1 | FileCheck %s --check-prefix=OK
// RUN: python3 %S/../../runtime/rocm/record_rocm.py --print-workload-contract | FileCheck %s --check-prefix=PYWL
// RUN: python3 %S/../../runtime/rocm/record_rocm.py --classify 10:10:10 | FileCheck %s --check-prefix=PYPAR

// Host protocol for the ROCm capability adapter. No device, no
// microseconds FileCheck, no Cost, no scheduler rewrite.
module {
}

// CHECK: s2c2-rocm-adapter dry-run=1
// CHECK: s2c2-rocm-adapter workload-contract=v1
// CHECK: s2c2-rocm-adapter workload id=compute role=compute semantic=elemwise
// CHECK: s2c2-rocm-adapter workload id=htod role=transfer semantic=host_to_device
// CHECK: s2c2-rocm-adapter workload id=dtoh role=transfer semantic=device_to_host
// CHECK: s2c2-rocm-adapter pair id=R1 name=C||HtoD
// CHECK: s2c2-rocm-adapter pair id=R2 name=C||C
// CHECK: s2c2-rocm-adapter pair id=R3 name=HtoD||DtoH
// CHECK: s2c2-rocm-adapter correctness=1
// CHECK: s2c2-rocm-adapter map stor.pack=host_pinned
// CHECK: s2c2-rocm-adapter map comm.stream=hipMemcpyAsync
// CHECK: s2c2-rocm-adapter map sched.concurrent=two_streams
// CHECK: s2c2-rocm-adapter note workload-semantic-ne-kernel-backend
// CHECK: s2c2-rocm-adapter cost=unchanged
// CHECK: s2c2-rocm-adapter v3=not-claimed
// CHECK-NOT: semantic=silu
// CHECK-NOT: tiled-gemm
// CHECK-NOT: cap=htod
// CHECK-NOT: hip_stream
// CHECK-NOT: amdgpu_
// CHECK-NOT: password
// CHECK-NOT: Cost v0.4

// PAIRS: s2c2-rocm-adapter pair=C||HtoD
// PAIRS: s2c2-rocm-adapter pair=C||C
// PAIRS: s2c2-rocm-adapter pair=HtoD||DtoH
// PAIRS: s2c2-rocm-adapter correctness=1
// PAIRS: s2c2-rocm-adapter score3=not-applicable
// PAIRS-NOT: pair=C_silu||C_gemm
// PAIRS-NOT: pair=HtoD||HtoD
// PAIRS-NOT: cap-schema=v1

// WL: s2c2-rocm-adapter workload compute=elemwise
// WL: s2c2-rocm-adapter workload transfer=host_to_device|device_to_host
// WL-NOT: semantic=silu
// WL-NOT: pair=C||HtoD

// PAR: s2c2-rocm-adapter classify pair_relation=parallel
// PAR: s2c2-rocm-adapter classify rule=par/max<=1.15,par/sum<=0.75->parallel
// PAR: s2c2-rocm-adapter classify cost=unchanged

// SER: s2c2-rocm-adapter classify pair_relation=serial
// SER: s2c2-rocm-adapter classify rule=par/sum>=0.90->serial

// MIX: s2c2-rocm-adapter classify pair_relation=mixed
// MIX: s2c2-rocm-adapter classify else=mixed

// EMIT: "schema_version":"1"
// EMIT: "hardware_id":"unfilled"
// EMIT: "compute_domain":"rocm_cu"
// EMIT: "pair_relation":"underdetermined"
// EMIT: "synchronization":"named-nonblocking"
// EMIT: "observed_constraint":"none"
// EMIT: "confidence":"unknown"
// EMIT: "v3":"not-claimed"
// EMIT: "cost":"unchanged"
// EMIT: s2c2-rocm-adapter emit-record pair=C||C confidence=unknown
// EMIT-NOT: hip_
// EMIT-NOT: "pair_relation":"serial"
// EMIT-NOT: "confidence":"measured"

// FOR: s2c2-rocm-adapter foreign-hardware=rejected id=sm89:rtx4090
// FOR: s2c2-rocm-adapter note capability-4090-ne-capability-amd

// OK: s2c2-rocm-adapter hardware-scope=this-profile id=gfx1100:amd
// OK-NOT: foreign-hardware=rejected

// PYWL: workload-contract v1
// PYWL: compute semantic=elemwise
// PYWL: pair R1 C||HtoD
// PYWL: pair R2 C||C
// PYWL: pair R3 HtoD||DtoH
// PYWL: note workload-semantic-ne-kernel-backend
// PYWL-NOT: silu
// PYWL-NOT: tiled-gemm

// PYPAR: record_rocm classify pair_relation=parallel
// PYPAR: record_rocm classify cost=unchanged
