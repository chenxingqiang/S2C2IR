// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-storage-measured-contract | FileCheck %s --check-prefix=CONTRACT
// RUN: s2c2-opt %S/storage-aware-pipeline.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1.jsonl" --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global-measured|hierarchy-global-cost-coincide' | FileCheck %s --check-prefix=PIPE
// RUN: s2c2-opt %S/storage-aware-pipeline.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep hierarchy-global-measured | FileCheck %s --check-prefix=NONE
// RUN: s2c2-opt %S/storage-hierarchy.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1.jsonl" --check-s2c2-execution 2>&1 | grep hierarchy-global-measured | FileCheck %s --check-prefix=HIER
// RUN: s2c2-opt %S/storage-global.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1.jsonl" --check-s2c2-execution 2>&1 | grep hierarchy-global-measured | FileCheck %s --check-prefix=TRUNC
// RUN: s2c2-opt %S/storage-aware-pipeline.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1.jsonl dump-schedule=%t.json" --check-s2c2-execution >/dev/null 2>&1
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-measured %t.json | FileCheck %s --check-prefix=AN
// RUN: s2c2-opt %S/storage-aware-pipeline.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1.jsonl" --s2c2-lower | FileCheck %s --check-prefix=LOWER
// RUN: s2c2-cuda-adapter --dry-run --storage-measured 2>&1 | FileCheck %s --check-prefix=CUDA
// RUN: s2c2-ascend-adapter --dry-run --storage-measured 2>&1 | FileCheck %s --check-prefix=ASCEND
// RUN: not s2c2-cuda-adapter --dry-run --storage-measured --storage-cost 2>&1 | FileCheck %s --check-prefix=EXCL

// Phase 5A: rank enumerated F(program) under policy=measured-storage-v1
// from candidate-local records. cost-v04 stays FROZEN. Does not invent
// members, does not retarget default-3g, does not rank a truncated
// product, and does not apply the measured winner as a rewrite.
// Do not FileCheck microseconds. No new Capability grid.

// CONTRACT: storage-measured compiler-driven=yes
// CONTRACT: note measured-ne-legality
// CONTRACT: note measured-ne-rewrite-license
// CONTRACT: note policy=measured-storage-v1
// CONTRACT: note default-3g-frozen
// CONTRACT: note cost-v04-structural-frozen
// CONTRACT: note do-not-filecheck-microseconds
// CONTRACT: note runtime-validation-pending
// CONTRACT: cost=unchanged
// CONTRACT-NOT: password

// PIPE: hierarchy-global-cost-coincide diverge=no
// PIPE: hierarchy-global-measured ranked=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PRESERVE|TRANSFER
// PIPE-SAME: policy=measured-storage-v1
// PIPE-SAME: note measured-ne-legality
// PIPE-SAME: note measured-ne-rewrite-license
// PIPE-SAME: note default-3g-frozen
// PIPE-SAME: note cost-v04-structural-frozen
// PIPE: hierarchy-global-measured-schedule enumerated=yes truncated=no
// PIPE-SAME: ranked-eq-default-3g=no
// PIPE-SAME: measured-count=2
// PIPE: hierarchy-global-measured-diverge diverge=yes
// PIPE-SAME: note runtime-validation-pending
// PIPE: hierarchy-global-measured-candidate
// PIPE-SAME: evidence=yes
// PIPE-NOT: 12400
// PIPE-NOT: 10800

// NONE: hierarchy-global-measured ranked=not-measured
// NONE: hierarchy-global-measured-diverge diverge=n/a
// NONE-NOT: hierarchy-global-measured-candidate

// HIER: hierarchy-global-measured ranked=not-measured
// HIER: hierarchy-global-measured-diverge diverge=n/a
// HIER-NOT: hierarchy-global-measured ranked=MATERIALIZE

// TRUNC: hierarchy-global-measured ranked=not-enumerated
// TRUNC: hierarchy-global-measured-diverge diverge=n/a
// TRUNC-NOT: hierarchy-global-measured-candidate

// AN: storage-measured ranked=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PRESERVE|TRANSFER
// AN: storage-measured enumerated=yes
// AN: storage-measured ranked-eq-default-3g=no
// AN: storage-measured measured-count=2
// AN: storage-measured diverge=yes
// AN: storage-measured policy=measured-storage-v1
// AN: note cost-v04-structural-frozen
// AN: cost=unchanged
// AN-NOT: 12400
// AN-NOT: 10800

// CUDA: s2c2-cuda-adapter storage-measured=1
// CUDA: s2c2-cuda-adapter storage-measured policy=measured-storage-v1
// CUDA: s2c2-cuda-adapter storage-measured note measured-ne-rewrite-license
// CUDA: s2c2-cuda-adapter storage-measured note cost-v04-structural-frozen
// CUDA: s2c2-cuda-adapter storage-measured cost=unchanged

// ASCEND: s2c2-ascend-adapter storage-measured=1
// ASCEND: s2c2-ascend-adapter storage-measured policy=measured-storage-v1
// ASCEND: s2c2-ascend-adapter storage-measured note measured-ne-rewrite-license
// ASCEND: s2c2-ascend-adapter storage-measured cost=unchanged

// EXCL: cannot combine

// LOWER: memref.copy
// LOWER-NOT: sched.wait
// LOWER-NOT: comm.stream

module {
}
