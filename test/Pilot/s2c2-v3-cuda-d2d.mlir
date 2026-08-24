// RUN: s2c2-cuda-adapter --dry-run --cuda-val-d2d 2>&1 | FileCheck %s
// RUN: s2c2-cuda-adapter --dry-run --cuda-val-async 2>&1 | FileCheck %s --check-prefix=ASYNC
// RUN: s2c2-cuda-adapter --dry-run --cuda-val 2>&1 | FileCheck %s --check-prefix=V1
// RUN: s2c2-cuda-adapter --dry-run --cuda-val-mem 2>&1 | FileCheck %s --check-prefix=V2
// RUN: s2c2-cuda-adapter --dry-run --cuda-val-cc 2>&1 | FileCheck %s --check-prefix=CC
// RUN: s2c2-cuda-adapter --dry-run 2>&1 | FileCheck %s --check-prefix=ABC
// RUN: python3 %S/../../runtime/cuda/record_v3.py --print-cuda-val-d2d-schema | FileCheck %s --check-prefix=SCHEMA
// RUN: python3 %S/../../runtime/cuda/record_v3.py --analyze-cuda-val-d2d %S/cuda-val-d2d-fixture.jsonl | FileCheck %s --check-prefix=AN
// RUN: python3 %S/../../runtime/cuda/record_v3.py --analyze-cuda-val-d2d %S/../../docs/design/v3-dataset/v3-cuda-d2d.jsonl | FileCheck %s --check-prefix=HW

// Host + recorder protocol for same-device D2D Communication Domain.
// No device, no microseconds FileCheck, no Cost change. P2P is later.
module {
}

// CHECK: s2c2-cuda-adapter dry-run=1
// CHECK: s2c2-cuda-adapter cuda-val-d2d=p0
// CHECK: s2c2-cuda-adapter cuda-val-d2d map comm.copy=cudaMemcpyAsync
// CHECK: s2c2-cuda-adapter cuda-val-d2d map comm.d2d=cudaMemcpyDeviceToDevice
// CHECK: s2c2-cuda-adapter cuda-val-d2d map comm.p2p=out-of-increment
// CHECK: s2c2-cuda-adapter cuda-val-d2d map sched.concurrent=named-nonblocking-streams
// CHECK: s2c2-cuda-adapter cuda-val-d2d cell same-device-d2d
// CHECK: s2c2-cuda-adapter cuda-val-d2d cell d2d-vs-htod
// CHECK: s2c2-cuda-adapter cuda-val-d2d cell C||D2D
// CHECK: s2c2-cuda-adapter cuda-val-d2d cell D2D||D2D
// CHECK: s2c2-cuda-adapter cuda-val-d2d cell pair-relation=serial|parallel|mixed
// CHECK: s2c2-cuda-adapter cuda-val-d2d cell observed-constraint=none|copy_engine_contention
// CHECK: s2c2-cuda-adapter cuda-val-d2d cell extra-hb=not-applicable
// CHECK: s2c2-cuda-adapter cuda-val-d2d note p2p-needs-two-devices
// CHECK: s2c2-cuda-adapter cuda-val-d2d note d2d-not-extra-hb
// CHECK: s2c2-cuda-adapter cuda-val-d2d pair=C||D2D
// CHECK: s2c2-cuda-adapter cuda-val-d2d pair=D2D||D2D
// CHECK: s2c2-cuda-adapter cuda-val-d2d acceptance=communication-domain
// CHECK: s2c2-cuda-adapter cuda-val-d2d cost=unchanged
// CHECK: s2c2-cuda-adapter cuda-val-d2d semantics=unchanged
// CHECK: s2c2-cuda-adapter v3=not-claimed
// CHECK-NOT: extra-hb=copy-engine
// CHECK-NOT: cuda-val-async=v2p1
// CHECK-NOT: cuda-val=v1
// CHECK-NOT: cuda-val-mem=v2
// CHECK-NOT: func=pilot_a
// CHECK-NOT: password
// CHECK-NOT: Cost v0.4

// ASYNC: s2c2-cuda-adapter cuda-val-async=v2p1
// ASYNC-NOT: cuda-val-d2d=p0

// V1: s2c2-cuda-adapter cuda-val=v1
// V1-NOT: cuda-val-d2d=p0

// V2: s2c2-cuda-adapter cuda-val-mem=v2
// V2-NOT: cuda-val-d2d=p0

// CC: s2c2-cuda-adapter cuda-val-cc=p0
// CC-NOT: cuda-val-d2d=p0

// ABC: s2c2-cuda-adapter func=pilot_a_ssd_hbm_compute
// ABC-NOT: cuda-val-d2d=p0

// SCHEMA: cuda-val-d2d p0
// SCHEMA: comm same-device-d2d
// SCHEMA: p2p out-of-increment
// SCHEMA: pair C||D2D
// SCHEMA: pair D2D||D2D
// SCHEMA: acceptance communication-domain
// SCHEMA: observed-constraint none|copy_engine_contention
// SCHEMA: extra-hb not-applicable
// SCHEMA: d2d-not-extra-hb
// SCHEMA: semantics unchanged
// SCHEMA: v3=not-claimed
// SCHEMA: cost=unchanged

// AN: v3-cuda-val-d2d p0 comm=same-device-d2d p2p=out-of-increment
// AN: acceptance=communication-domain
// AN: copy_engine_contention
// AN: extra-hb=not-applicable
// AN: copy-engine-contention=3
// AN: d2d-not-extra-hb
// AN: same-device-d2d
// AN: communication-domain
// AN: semantics=unchanged
// AN: v3=not-claimed
// AN-NOT: extra-hb=copy-engine
// AN-NOT: Cost v0.4
// AN-NOT: password

// Qualitative 4090 surface only. Do not FileCheck microseconds.
// HW: v3-cuda-val-d2d p0 comm=same-device-d2d p2p=out-of-increment
// HW: acceptance=communication-domain
// HW: pair
// HW: C||HtoD
// HW: C||D2D
// HW: D2D||D2D
// HW: copy-engine-contention=3
// HW: extra-hb=not-applicable
// HW: d2d-not-extra-hb
// HW: semantics=unchanged
// HW: v3=not-claimed
// HW-NOT: extra-hb=copy-engine
// HW-NOT: Cost v0.4
// HW-NOT: password
