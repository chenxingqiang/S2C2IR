// RUN: python3 %S/../../runtime/record_evidence.py --print-stable-baseline-contract | FileCheck %s --check-prefix=BASE
// RUN: python3 %S/../../runtime/record_evidence.py --print-evidence-db-contract | FileCheck %s --check-prefix=EVI
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-schedule-policy-contract | FileCheck %s --check-prefix=POL
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-storage-measured-contract | FileCheck %s --check-prefix=MEAS
// RUN: python3 %S/../../runtime/record_evidence.py --check-evidence-db | FileCheck %s --check-prefix=DB
// RUN: s2c2-opt %S/storage-aware-pipeline.mlir --profile=rtx4090 --schedule-policy=default-3g --check-s2c2-execution 2>&1 | grep s2c2-schedule-policy | FileCheck %s --check-prefix=API
// RUN: s2c2-opt %S/storage-loop.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --s2c2-lower | FileCheck %s --check-prefix=LOWER

// Freeze 5A-6B as the stable compiler baseline. 5E and 6C
// are not opened. Do not retune 5A-5D. Do not change #69,
// cost-v04, default-3g, or the Evidence DB contract.
// Do not FileCheck microseconds.

// BASE: stable-baseline compiler-facing=yes
// BASE: stack 5A-5D|6A|6B
// BASE: note campaign-5a-5d-frozen
// BASE: note production-path-6a
// BASE: note evidence-db-v1
// BASE: note export-revision-required
// BASE: note query-revision-optional
// BASE: note identity-immutable
// BASE: note measured-ne-rewrite-license
// BASE: note default-3g-frozen
// BASE: note cost-v04-structural-frozen
// BASE: note five-e-not-opened
// BASE: note six-c-not-opened
// BASE: note not-capacity-aware
// BASE: note not-new-keep-transfer-rule
// BASE: note evidence-reuse-for-later-6c
// BASE: note do-not-filecheck-microseconds
// BASE: cost=unchanged
// BASE-NOT: password
// BASE-NOT: 223.72
// BASE-NOT: 106.75
// BASE-NOT: sched.wait

// EVI: note export-revision-required
// EVI: note stable-baseline
// EVI: note six-c-not-opened
// EVI: cost=unchanged

// POL: note not-capacity-aware
// POL: note stable-baseline
// POL: note six-c-not-opened
// POL: cost=unchanged

// MEAS: note campaign-5a-5d-frozen
// MEAS: note stable-baseline
// MEAS: note six-c-not-opened
// MEAS: cost=unchanged

// DB: evidence-db check=ok records=38
// DB: evidence-db measured=36 fixture=2 other=0
// DB: evidence-db note identity-E-unique
// DB-NOT: 8495
// DB-NOT: 10303
// DB-NOT: 6791

// API: s2c2-schedule-policy name=default-3g{{.*}}rewrite=no
// API-NOT: sched.wait

// LOWER: scf.for
// LOWER-NOT: sched.wait
// LOWER-NOT: comm.stream

module {
}
