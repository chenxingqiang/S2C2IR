// RUN: s2c2-cuda-adapter --dry-run --cuda-val-async 2>&1 | FileCheck %s
// RUN: s2c2-cuda-adapter --dry-run --cuda-val 2>&1 | FileCheck %s --check-prefix=V1
// RUN: s2c2-cuda-adapter --dry-run --cuda-val-cc 2>&1 | FileCheck %s --check-prefix=CC
// RUN: s2c2-cuda-adapter --dry-run 2>&1 | FileCheck %s --check-prefix=ABC
// RUN: python3 %S/../../runtime/cuda/record_v3.py --print-cuda-val-async-schema | FileCheck %s --check-prefix=SCHEMA
// RUN: python3 %S/../../runtime/cuda/record_v3.py --analyze-cuda-val-async %S/cuda-val-async-fixture.jsonl | FileCheck %s --check-prefix=AN
// RUN: python3 %S/../../runtime/cuda/record_v3.py --analyze-cuda-val-async %S/../../docs/design/v3-dataset/v3-cuda-async.jsonl | FileCheck %s --check-prefix=HW

// Host + recorder protocol for async alloc + cross-stream wait.
// No device, no microseconds FileCheck, no Cost change.
module {
}

// CHECK: s2c2-cuda-adapter dry-run=1
// CHECK: s2c2-cuda-adapter cuda-val-async=v2p1
// CHECK: s2c2-cuda-adapter cuda-val-async map stor.materialize=cudaMallocAsync
// CHECK: s2c2-cuda-adapter cuda-val-async map stor.release=cudaFreeAsync
// CHECK: s2c2-cuda-adapter cuda-val-async map sched.wait=cudaStreamWaitEvent
// CHECK: s2c2-cuda-adapter cuda-val-async chain materialize->write->event->wait->read->release
// CHECK: s2c2-cuda-adapter cuda-val-async cell alloc-sync
// CHECK: s2c2-cuda-adapter cuda-val-async cell alloc-async
// CHECK: s2c2-cuda-adapter cuda-val-async cell observed-constraint=none|allocator_sync
// CHECK: s2c2-cuda-adapter cuda-val-async cell extra-hb=not-applicable
// CHECK: s2c2-cuda-adapter cuda-val-async note legal-wait-not-extra-hb
// CHECK: s2c2-cuda-adapter cuda-val-async cost=unchanged
// CHECK: s2c2-cuda-adapter cuda-val-async semantics=unchanged
// CHECK: s2c2-cuda-adapter v3=not-claimed
// CHECK-NOT: extra-hb=sync-alloc
// CHECK-NOT: cuda-val=v1
// CHECK-NOT: cuda-val-mem=v2
// CHECK-NOT: func=pilot_a
// CHECK-NOT: password

// V1: s2c2-cuda-adapter cuda-val=v1
// V1-NOT: cuda-val-async=v2p1

// V2: s2c2-cuda-adapter cuda-val-mem=v2
// V2-NOT: cuda-val-async=v2p1

// CC: s2c2-cuda-adapter cuda-val-cc=p0
// CC-NOT: cuda-val-async=v2p1

// ABC: s2c2-cuda-adapter func=pilot_a_ssd_hbm_compute
// ABC-NOT: cuda-val-async=v2p1

// SCHEMA: cuda-val-async v2p1
// SCHEMA: chain materialize->write->event->wait->read->release
// SCHEMA: observed-constraint none|allocator_sync
// SCHEMA: extra-hb not-applicable
// SCHEMA: legal-wait-not-extra-hb
// SCHEMA: semantics unchanged
// SCHEMA: v3=not-claimed
// SCHEMA: cost=unchanged

// AN: v3-cuda-val-async v2p1 chain=materialize-write-event-wait-read-release
// AN: observed_constraint
// AN: allocator_sync
// AN: extra-hb=not-applicable
// AN: allocator-sync=3
// AN: legal-wait-not-extra-hb
// AN: semantics=unchanged
// AN: v3=not-claimed
// AN-NOT: extra-hb=sync-alloc
// AN-NOT: Cost v0.4
// AN-NOT: password

// Qualitative 4090 surface only. Do not FileCheck microseconds.
// HW: v3-cuda-val-async v2p1 chain=materialize-write-event-wait-read-release
// HW: allocator-sync=0
// HW: extra-hb=not-applicable
// HW: legal-wait-not-extra-hb
// HW: semantics=unchanged
// HW: v3=not-claimed
// HW-NOT: extra-hb=sync-alloc
// HW-NOT: Cost v0.4
// HW-NOT: password
