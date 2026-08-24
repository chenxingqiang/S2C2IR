// RUN: s2c2-ascend-adapter --dry-run --cc-size 2>&1 | FileCheck %s
// RUN: s2c2-ascend-adapter --dry-run --cc-phase 2>&1 | FileCheck %s --check-prefix=PHASE
// RUN: not s2c2-ascend-adapter --dry-run --cc-phase --cc-size 2>&1 | FileCheck %s --check-prefix=EXCL
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-cc-size-schema | FileCheck %s --check-prefix=SCHEMA
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-cc-size %S/ascend-cc-size-fixture.log | FileCheck %s --check-prefix=AN
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --query-cap 'C||C' --cap-catalog %S/../../docs/design/v3-dataset/ascend910b/capability.jsonl | FileCheck %s --check-prefix=QC

// Host protocol for 910B C||C size-boundary at r≈1. No microseconds FileCheck.
module {
}

// CHECK: s2c2-ascend-adapter dry-run=1
// CHECK: s2c2-ascend-adapter cc-size=1
// CHECK: s2c2-ascend-adapter cc-size pair=C||C
// CHECK: s2c2-ascend-adapter cc-size r=1
// CHECK: s2c2-ascend-adapter cc-size n=4M,8M,12M,16M,32M,64M,128M
// CHECK: s2c2-ascend-adapter cc-size note size-boundary
// CHECK: s2c2-ascend-adapter cc-size r3-gate=closed
// CHECK: s2c2-ascend-adapter cc-size note catalog-untouched
// CHECK: s2c2-ascend-adapter cc-size cost=unchanged
// CHECK-NOT: password
// CHECK-NOT: Cost v0.4

// PHASE: s2c2-ascend-adapter cc-phase=1
// PHASE-NOT: cc-size=1

// EXCL: cannot combine

// SCHEMA: ascend-cc-size pair=C||C
// SCHEMA: r=1
// SCHEMA: note size-boundary
// SCHEMA: r3-gate=closed
// SCHEMA: note catalog-untouched
// SCHEMA: v3=not-claimed
// SCHEMA: cost=unchanged

// AN: v3-ascend-cc-size pair=C||C r=1 r3-gate=closed
// AN: n-grid=4M,8M,16M
// AN: transition=mixed-to-serial 8M..16M
// AN: r3-gate=closed
// AN: note catalog-untouched
// AN: v3=not-claimed
// AN-NOT: Cost v0.4
// AN-NOT: password

// #69 C||C stays underdetermined.
// QC: "pair":"C||C"
// QC: "pair_relation":"underdetermined"
// QC: "applicable":false
// QC-NOT: password
