// RUN: s2c2-ascend-adapter --dry-run 2>&1 | FileCheck %s
// RUN: s2c2-ascend-adapter --dry-run --pairs 2>&1 | FileCheck %s --check-prefix=PAIRS
// RUN: s2c2-ascend-adapter --dry-run --workload 2>&1 | FileCheck %s --check-prefix=WL
// RUN: s2c2-ascend-adapter --dry-run --classify=10:10:10 2>&1 | FileCheck %s --check-prefix=PAR
// RUN: s2c2-ascend-adapter --dry-run --classify=10:10:19.5 2>&1 | FileCheck %s --check-prefix=SER
// RUN: s2c2-ascend-adapter --dry-run --classify=10:10:16 2>&1 | FileCheck %s --check-prefix=MIX
// RUN: s2c2-ascend-adapter --dry-run --emit-record='C||C' 2>&1 | FileCheck %s --check-prefix=EMIT
// RUN: not s2c2-ascend-adapter --dry-run --accept-hardware=sm89:rtx4090 2>&1 | FileCheck %s --check-prefix=FOR
// RUN: s2c2-ascend-adapter --dry-run --accept-hardware=ascend910b:ascend 2>&1 | FileCheck %s --check-prefix=OK
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-workload-contract | FileCheck %s --check-prefix=PYWL
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --classify 10:10:10 | FileCheck %s --check-prefix=PYPAR

// Host protocol for the Ascend 910B capability adapter. No device,
// no microseconds FileCheck, no Cost, no scheduler rewrite.
module {
}

// CHECK: s2c2-ascend-adapter dry-run=1
// CHECK: s2c2-ascend-adapter workload-contract=v1
// CHECK: s2c2-ascend-adapter workload id=compute role=compute semantic=elemwise
// CHECK: s2c2-ascend-adapter workload id=htod role=transfer semantic=host_to_device
// CHECK: s2c2-ascend-adapter workload id=dtoh role=transfer semantic=device_to_host
// CHECK: s2c2-ascend-adapter pair id=R1 name=C||HtoD
// CHECK: s2c2-ascend-adapter pair id=R2 name=C||C
// CHECK: s2c2-ascend-adapter pair id=R3 name=HtoD||DtoH
// CHECK: s2c2-ascend-adapter timing=host-wall-clock
// CHECK: s2c2-ascend-adapter timing completion=s0,s1
// CHECK: s2c2-ascend-adapter correctness=1
// CHECK: s2c2-ascend-adapter map stor.pack=host_pinned
// CHECK: s2c2-ascend-adapter map comm.stream=aclrtMemcpyAsync
// CHECK: s2c2-ascend-adapter map sched.wait=aclrtRecordEvent+aclrtStreamWaitEvent
// CHECK: s2c2-ascend-adapter map event=submitted-work-on-stream
// CHECK: s2c2-ascend-adapter map sched.concurrent=two_streams
// CHECK: s2c2-ascend-adapter note workload-semantic-ne-kernel-backend
// CHECK: s2c2-ascend-adapter cost=unchanged
// CHECK: s2c2-ascend-adapter v3=not-claimed
// CHECK-NOT: semantic=silu
// CHECK-NOT: tiled-gemm
// CHECK-NOT: cap=htod
// CHECK-NOT: acl_stream
// CHECK-NOT: davinci_
// CHECK-NOT: cube_
// CHECK-NOT: password
// CHECK-NOT: Cost v0.4

// PAIRS: s2c2-ascend-adapter pair=C||HtoD
// PAIRS: s2c2-ascend-adapter pair=C||C
// PAIRS: s2c2-ascend-adapter pair=HtoD||DtoH
// PAIRS: s2c2-ascend-adapter timing=host-wall-clock
// PAIRS: s2c2-ascend-adapter timing completion=s0,s1
// PAIRS: s2c2-ascend-adapter correctness=1
// PAIRS: s2c2-ascend-adapter score3=not-applicable
// PAIRS-NOT: pair=C_silu||C_gemm
// PAIRS-NOT: pair=HtoD||HtoD
// PAIRS-NOT: cap-schema=v1

// WL: s2c2-ascend-adapter workload compute=elemwise
// WL: s2c2-ascend-adapter workload transfer=host_to_device|device_to_host
// WL-NOT: semantic=silu
// WL-NOT: pair=C||HtoD

// PAR: s2c2-ascend-adapter classify pair_relation=parallel
// PAR: s2c2-ascend-adapter classify rule=par/max<=1.15,par/sum<=0.75->parallel
// PAR: s2c2-ascend-adapter classify cost=unchanged

// SER: s2c2-ascend-adapter classify pair_relation=serial
// SER: s2c2-ascend-adapter classify rule=par/sum>=0.90->serial

// MIX: s2c2-ascend-adapter classify pair_relation=mixed
// MIX: s2c2-ascend-adapter classify else=mixed

// EMIT: "schema_version":"1"
// EMIT: "hardware_id":"unfilled"
// EMIT: "compute_domain":"ascend_ai_core"
// EMIT: "pair_relation":"underdetermined"
// EMIT: "synchronization":"named-nonblocking"
// EMIT: "observed_constraint":"none"
// EMIT: "confidence":"unknown"
// EMIT: "v3":"not-claimed"
// EMIT: "cost":"unchanged"
// EMIT: s2c2-ascend-adapter emit-record pair=C||C confidence=unknown
// EMIT-NOT: acl_
// EMIT-NOT: "pair_relation":"serial"
// EMIT-NOT: "confidence":"measured"

// FOR: s2c2-ascend-adapter foreign-hardware=rejected id=sm89:rtx4090
// FOR: s2c2-ascend-adapter note capability-4090-ne-capability-910b

// OK: s2c2-ascend-adapter hardware-scope=this-profile id=ascend910b:ascend
// OK-NOT: foreign-hardware=rejected

// PYWL: workload-contract v1
// PYWL: compute semantic=elemwise
// PYWL: pair R1 C||HtoD
// PYWL: pair R2 C||C
// PYWL: pair R3 HtoD||DtoH
// PYWL: note workload-semantic-ne-kernel-backend
// PYWL-NOT: silu
// PYWL-NOT: tiled-gemm

// PYPAR: record_ascend classify pair_relation=parallel
// PYPAR: record_ascend classify cost=unchanged
