// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-storage-measured-contract | FileCheck %s --check-prefix=CONTRACT
// RUN: s2c2-opt %S/storage-aware-pipeline.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1-4090.jsonl" --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global-measured-diverge|hierarchy-global-measured-schedule' | FileCheck %s --check-prefix=A4090
// RUN: s2c2-opt %S/storage-aware-pipeline.mlir --s2c2-evidence-bounded-schedule="profile=910B measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1-910b.jsonl" --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global-measured-diverge|hierarchy-global-measured-schedule' | FileCheck %s --check-prefix=A910B
// RUN: s2c2-opt %S/storage-hierarchy.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1-hierarchy-4090.jsonl" --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global-measured-diverge|hierarchy-global-measured-schedule' | FileCheck %s --check-prefix=B4090
// RUN: s2c2-opt %S/storage-hierarchy.mlir --s2c2-evidence-bounded-schedule="profile=910B measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1-hierarchy-910b.jsonl" --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global-measured-diverge|hierarchy-global-measured-schedule' | FileCheck %s --check-prefix=B910B
// RUN: s2c2-opt %S/storage-ntile.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1-ntile-4090.jsonl" --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global-measured-diverge|hierarchy-global-measured-schedule' | FileCheck %s --check-prefix=C4090
// RUN: s2c2-opt %S/storage-ntile.mlir --s2c2-evidence-bounded-schedule="profile=910B measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1-ntile-910b.jsonl" --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global-measured-diverge|hierarchy-global-measured-schedule' | FileCheck %s --check-prefix=C910B
// RUN: s2c2-opt %S/storage-loop.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1-loop-4090.jsonl" --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global-measured-diverge|hierarchy-global-measured-schedule' | FileCheck %s --check-prefix=D4090
// RUN: s2c2-opt %S/storage-loop.mlir --s2c2-evidence-bounded-schedule="profile=910B measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1-loop-910b.jsonl" --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global-measured-diverge|hierarchy-global-measured-schedule' | FileCheck %s --check-prefix=D910B
// RUN: s2c2-opt %S/storage-loop.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --s2c2-lower | FileCheck %s --check-prefix=LOWER

// Campaign freeze of Phases 5A–5D. Every existing enumerated
// Storage F ranked under measured-storage-v1 on both devices.
// ArgMin is default-3g every time (diverge=no). That is a
// complete positive result. 5E is not opened. Do not hunt
// for diverge=yes. Do not retune n/k/trip. Do not invent S4.
// Do not FileCheck microseconds. #69 untouched.

// CONTRACT: note measured-ne-rewrite-license
// CONTRACT: note cost-v04-structural-frozen
// CONTRACT: note measurement-cannot-expand-F
// CONTRACT: note diverge-yes-not-goal
// CONTRACT: note campaign-5a-5d-frozen
// CONTRACT: note five-e-not-opened
// CONTRACT: note do-not-hunt-diverge
// CONTRACT: note do-not-retune-workload
// CONTRACT: note do-not-invent-s4
// CONTRACT: cost=unchanged
// CONTRACT-NOT: password
// CONTRACT-NOT: 223.72
// CONTRACT-NOT: 106.75

// A4090: ranked-eq-default-3g=yes
// A4090: hierarchy-global-measured-diverge diverge=no
// A4090-NOT: 10303
// A4090-NOT: 8495

// A910B: ranked-eq-default-3g=yes
// A910B: hierarchy-global-measured-diverge diverge=no
// A910B-NOT: 7463
// A910B-NOT: 6791

// B4090: ranked-eq-default-3g=yes
// B4090: hierarchy-global-measured-diverge diverge=no

// B910B: ranked-eq-default-3g=yes
// B910B: hierarchy-global-measured-diverge diverge=no

// C4090: ranked-eq-default-3g=yes
// C4090: hierarchy-global-measured-diverge diverge=no
// C4090-NOT: 10303
// C4090-NOT: 11084

// C910B: ranked-eq-default-3g=yes
// C910B: hierarchy-global-measured-diverge diverge=no
// C910B-NOT: 7463
// C910B-NOT: 8798

// D4090: ranked-eq-default-3g=yes
// D4090: hierarchy-global-measured-diverge diverge=no
// D4090-NOT: 8495
// D4090-NOT: 13713

// D910B: ranked-eq-default-3g=yes
// D910B: hierarchy-global-measured-diverge diverge=no
// D910B-NOT: 6791
// D910B-NOT: 11130

// LOWER: scf.for
// LOWER-NOT: sched.wait
// LOWER-NOT: comm.stream

module {
}
