// RUN: s2c2-ascend-adapter --dry-run --mem 2>&1 | FileCheck %s
// RUN: s2c2-ascend-adapter --dry-run --pairs 2>&1 | FileCheck %s --check-prefix=PAIRS
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-mem-schema | FileCheck %s --check-prefix=SCHEMA
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-mem %S/ascend-mem-fixture.log | FileCheck %s --check-prefix=AN
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-mem %S/../../docs/design/v3-dataset/ascend910b/mem.log | FileCheck %s --check-prefix=HW
// RUN: FileCheck %s --check-prefix=JSONL < %S/../../docs/design/v3-dataset/ascend910b/mem.jsonl

// Host protocol for 910B pinned vs pageable. No microseconds FileCheck.
module {
}

// CHECK: s2c2-ascend-adapter dry-run=1
// CHECK: s2c2-ascend-adapter mem=r4
// CHECK: s2c2-ascend-adapter mem map stor.host=pinned|pageable
// CHECK: s2c2-ascend-adapter mem map stor.pinned=aclrtMallocHost
// CHECK: s2c2-ascend-adapter mem map stor.pageable=malloc
// CHECK: s2c2-ascend-adapter mem map comm.copy=aclrtMemcpyAsync
// CHECK: s2c2-ascend-adapter mem cell host-pinned
// CHECK: s2c2-ascend-adapter mem cell host-pageable
// CHECK: s2c2-ascend-adapter mem cell extra-hb=pageable-host
// CHECK: s2c2-ascend-adapter mem pair=C||HtoD
// CHECK: s2c2-ascend-adapter mem pair=C||DtoH
// CHECK: s2c2-ascend-adapter mem acceptance=storage-comm
// CHECK: s2c2-ascend-adapter mem note residency-ne-extra-hb
// CHECK: s2c2-ascend-adapter mem cost=unchanged
// CHECK-NOT: pair=C||C
// CHECK-NOT: password
// CHECK-NOT: Cost v0.4

// PAIRS: s2c2-ascend-adapter pair=C||HtoD
// PAIRS-NOT: mem=r4

// SCHEMA: ascend-mem r4
// SCHEMA: pair C||HtoD C||DtoH
// SCHEMA: host pinned pageable
// SCHEMA: acceptance storage-comm
// SCHEMA: extra-hb none|pageable-host
// SCHEMA: note residency-ne-extra-hb
// SCHEMA: size_range payload-bytes
// SCHEMA: note size_range-ne-N-label
// SCHEMA: v3=not-claimed
// SCHEMA: cost=unchanged

// AN: v3-ascend-mem r4 pair=C||HtoD,C||DtoH acceptance=storage-comm
// AN: size_range=16MiB
// AN: measured sizes = 16MiB
// AN: extra-hb=pageable-host
// AN: counterexamples=1
// AN: note residency-ne-extra-hb
// AN: v3=not-claimed
// AN-NOT: size_range=4MiB
// AN-NOT: Cost v0.4
// AN-NOT: password

// Qualitative 910B surface only. Do not FileCheck microseconds.
// Schema v1 size_range is payload bytes (N floats * 4), not the N label.
// HW: v3-ascend-mem r4 pair=C||HtoD,C||DtoH acceptance=storage-comm
// HW: size_range=16MiB..256MiB
// HW: measured sizes = 16MiB,64MiB,256MiB
// HW: counterexamples=0
// HW: note residency-ne-extra-hb
// HW: semantics=unchanged
// HW: v3=not-claimed
// HW-NOT: size_range=4MiB..64MiB
// HW-NOT: extra-hb=pageable-host
// HW-NOT: Cost v0.4
// HW-NOT: password

// JSONL: "size_range":"16MiB..256MiB"
// JSONL: measured sizes = 16MiB,64MiB,256MiB
// JSONL: "size_range":"16MiB..256MiB"
// JSONL: measured sizes = 16MiB,64MiB,256MiB
// JSONL-NOT: "size_range":"4MiB..64MiB"
