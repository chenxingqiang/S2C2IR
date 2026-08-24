// RUN: s2c2-ascend-adapter --dry-run --cc-phase 2>&1 | FileCheck %s
// RUN: s2c2-ascend-adapter --dry-run --pairs 2>&1 | FileCheck %s --check-prefix=PAIRS
// RUN: not s2c2-ascend-adapter --dry-run --mem --cc-phase 2>&1 | FileCheck %s --check-prefix=EXCL
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-cc-phase-schema | FileCheck %s --check-prefix=SCHEMA
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-cc-phase %S/ascend-cc-phase-fixture.log | FileCheck %s --check-prefix=AN
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --query-cap 'C||C' --cap-catalog %S/../../docs/design/v3-dataset/ascend910b/capability.jsonl | FileCheck %s --check-prefix=QC

// Host protocol for 910B C||C r-sweep. No microseconds FileCheck.
module {
}

// CHECK: s2c2-ascend-adapter dry-run=1
// CHECK: s2c2-ascend-adapter cc-phase=1
// CHECK: s2c2-ascend-adapter cc-phase pair=C||C
// CHECK: s2c2-ascend-adapter cc-phase r=T_C1/T_C2
// CHECK: s2c2-ascend-adapter cc-phase r_target=0.5,0.75,1,1.5,2
// CHECK: s2c2-ascend-adapter cc-phase n=4M,16M,64M
// CHECK: s2c2-ascend-adapter cc-phase r3-gate=closed
// CHECK: s2c2-ascend-adapter cc-phase note catalog-untouched
// CHECK: s2c2-ascend-adapter cc-phase cost=unchanged
// CHECK-NOT: pair=C||HtoD
// CHECK-NOT: password
// CHECK-NOT: Cost v0.4

// PAIRS: s2c2-ascend-adapter pair=C||HtoD
// PAIRS-NOT: cc-phase=1

// EXCL: cannot combine

// SCHEMA: ascend-cc-phase pair=C||C
// SCHEMA: r=T_C1/T_C2
// SCHEMA: r3-gate=closed
// SCHEMA: note catalog-untouched
// SCHEMA: v3=not-claimed
// SCHEMA: cost=unchanged

// AN: v3-ascend-cc-phase pair=C||C r3-gate=closed
// AN: unique=no
// AN: r3-gate=closed
// AN: note catalog-untouched
// AN: v3=not-claimed
// AN-NOT: unique=yes
// AN-NOT: Cost v0.4
// AN-NOT: password

// #69 C||C stays underdetermined until a unique applicable cell exists.
// QC: "pair":"C||C"
// QC: "pair_relation":"underdetermined"
// QC: "applicable":false
// QC-NOT: "pair_relation":"parallel"
// QC-NOT: password
