// RUN: s2c2-ascend-adapter --dry-run --cc-rewrite 2>&1 | FileCheck %s
// RUN: s2c2-ascend-adapter --dry-run --cc-size 2>&1 | FileCheck %s --check-prefix=SIZE
// RUN: not s2c2-ascend-adapter --dry-run --cc-rewrite --cc-size 2>&1 | FileCheck %s --check-prefix=EXCL
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-cc-rewrite-schema | FileCheck %s --check-prefix=SCHEMA
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-cc-rewrite %S/ascend-cc-rewrite-yes-fixture.log | FileCheck %s --check-prefix=YES
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-cc-rewrite %S/ascend-cc-rewrite-no-fixture.log | FileCheck %s --check-prefix=NO
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --query-cap 'C||C' --cap-catalog %S/../../docs/design/v3-dataset/ascend910b/capability.jsonl | FileCheck %s --check-prefix=QC
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --query-cap 'C||C' --cap-catalog %S/../../docs/design/v3-dataset/ascend910b/cc-size-applicability.jsonl --n 33554432 | FileCheck %s --check-prefix=QS
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-cc-rewrite %S/../../docs/design/v3-dataset/ascend910b/cc-rewrite.log | FileCheck %s --check-prefix=HW

// Host protocol: concurrent vs sequential C||C A/B. No microseconds.
// #69 stays underdetermined. Overlay serial band is rewrite-licensed
// from the 910B A/B. Not Cost. R3 closed.
module {
}

// CHECK: s2c2-ascend-adapter dry-run=1
// CHECK: s2c2-ascend-adapter cc-rewrite=1
// CHECK: s2c2-ascend-adapter cc-rewrite pair=C||C
// CHECK: s2c2-ascend-adapter cc-rewrite r=1
// CHECK: s2c2-ascend-adapter cc-rewrite n=32M,64M,128M
// CHECK: s2c2-ascend-adapter cc-rewrite ab=par-vs-seq
// CHECK: s2c2-ascend-adapter cc-rewrite seq=s0-then-s1
// CHECK: s2c2-ascend-adapter cc-rewrite seq-slack=1.05
// CHECK: s2c2-ascend-adapter cc-rewrite note seq-slack-ne-cost
// CHECK: s2c2-ascend-adapter cc-rewrite r3-gate=closed
// CHECK: s2c2-ascend-adapter cc-rewrite note catalog-untouched
// CHECK: s2c2-ascend-adapter cc-rewrite cost=unchanged
// CHECK-NOT: password
// CHECK-NOT: Cost v0.4

// SIZE: s2c2-ascend-adapter cc-size=1
// SIZE-NOT: cc-rewrite=1

// EXCL: cannot combine

// SCHEMA: ascend-cc-rewrite pair=C||C
// SCHEMA: r=1
// SCHEMA: n=32M,64M,128M
// SCHEMA: ab=par-vs-seq
// SCHEMA: seq-slack=1.05
// SCHEMA: note seq-slack-ne-cost
// SCHEMA: r3-gate=closed
// SCHEMA: note catalog-untouched
// SCHEMA: v3=not-claimed
// SCHEMA: cost=unchanged

// YES: v3-ascend-cc-rewrite pair=C||C r=1 r3-gate=closed
// YES: n-grid=32M,64M,128M
// YES: relations=serial
// YES: benefit=yes
// YES: rewrite_license=yes
// YES: r3-gate=closed
// YES: note catalog-untouched
// YES: v3=not-claimed
// YES-NOT: Cost v0.4
// YES-NOT: password

// Concurrent still faster than seq → no license.
// NO: v3-ascend-cc-rewrite pair=C||C r=1 r3-gate=closed
// NO: benefit=no
// NO: rewrite_license=no
// NO: r3-gate=closed
// NO-NOT: Cost v0.4

// #69 C||C stays underdetermined.
// QC: "pair":"C||C"
// QC: "pair_relation":"underdetermined"
// QC: "applicable":false
// QC-NOT: password

// Overlay serial band is rewrite-licensed from the 910B A/B.
// QS: "pair":"C||C"
// QS: "pair_relation":"serial"
// QS: "size_range":"128MiB..512MiB"
// QS: "rewrite_license":true
// QS-NOT: password

// Hardware log: analyzer tokens only. Do not FileCheck microseconds.
// HW: v3-ascend-cc-rewrite pair=C||C r=1 r3-gate=closed
// HW: n-grid=32M,64M,128M
// HW: relations=serial
// HW: benefit=yes
// HW: rewrite_license=yes
// HW: r3-gate=closed
// HW: note catalog-untouched
// HW: v3=not-claimed
// HW: cost=unchanged
// HW-NOT: Cost v0.4
// HW-NOT: password
