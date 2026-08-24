// RUN: s2c2-ascend-adapter --dry-run --mem 2>&1 | FileCheck %s
// RUN: s2c2-ascend-adapter --dry-run --pairs 2>&1 | FileCheck %s --check-prefix=PAIRS
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-mem-schema | FileCheck %s --check-prefix=SCHEMA
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-mem %S/ascend-mem-fixture.log | FileCheck %s --check-prefix=AN

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
// SCHEMA: v3=not-claimed
// SCHEMA: cost=unchanged

// AN: v3-ascend-mem r4 pair=C||HtoD,C||DtoH acceptance=storage-comm
// AN: extra-hb=pageable-host
// AN: counterexamples=1
// AN: note residency-ne-extra-hb
// AN: v3=not-claimed
// AN-NOT: Cost v0.4
// AN-NOT: password
