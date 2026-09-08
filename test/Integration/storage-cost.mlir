// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-storage-cost-contract | FileCheck %s --check-prefix=CONTRACT
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global-cost' | FileCheck %s --check-prefix=GPU-LOG
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=unknown --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global-cost' | FileCheck %s --check-prefix=UNK-LOG
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2> %t.gpu.err
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-cost %t.gpu.err | FileCheck %s --check-prefix=GPU-AN
// RUN: s2c2-opt %S/storage-hierarchy.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 dump-schedule=%t.json" --check-s2c2-execution >/dev/null 2>&1
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-cost %t.json | FileCheck %s --check-prefix=GPU-AN
// RUN: s2c2-opt %S/storage-global.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global-cost' | FileCheck %s --check-prefix=TRUNC
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --s2c2-lower | FileCheck %s --check-prefix=LOWER
// RUN: s2c2-cuda-adapter --dry-run --storage-cost 2>&1 | FileCheck %s --check-prefix=CUDA
// RUN: s2c2-ascend-adapter --dry-run --storage-cost 2>&1 | FileCheck %s --check-prefix=ASCEND
// RUN: not s2c2-cuda-adapter --dry-run --storage-cost --storage-global 2>&1 | FileCheck %s --check-prefix=EXCL

// Phase 4D: rank enumerated F(program) under policy=cost-v04.
// Does not invent members, does not retarget default-3g, and
// does not rank a truncated product. Frozen --s2c2-cost /
// --s2c2-argmin / Score_3 untouched. No new Capability grid.
// No C||Storage flatten. Do not FileCheck microseconds.

// CONTRACT: storage-cost compiler-driven=yes
// CONTRACT: no-evidence => no-destructive-optimization
// CONTRACT: note cost-ranks-enumerated-F-only
// CONTRACT: note cost-ne-legality
// CONTRACT: note cost-ne-rewrite-license
// CONTRACT: note policy=cost-v04
// CONTRACT: note default-3g-frozen
// CONTRACT: note truncated-ne-ranked
// CONTRACT: note not-s2c2-argmin
// CONTRACT: note not-score3
// CONTRACT: note not-new-capability-grid
// CONTRACT: cost=unchanged
// CONTRACT-NOT: password

// GPU-LOG: hierarchy-global-cost ranked=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
// GPU-LOG-SAME: score=0
// GPU-LOG-SAME: policy=cost-v04
// GPU-LOG-SAME: note cost-ne-legality
// GPU-LOG-SAME: note default-3g-frozen
// GPU-LOG-SAME: note truncated-ne-ranked
// GPU-LOG: hierarchy-global-cost-schedule enumerated=yes truncated=no
// GPU-LOG-SAME: ranked-in-legal=yes
// GPU-LOG-SAME: ranked-eq-default-3g=yes
// GPU-LOG-SAME: argmin-size=1
// GPU-LOG: hierarchy-global-cost-candidate
// GPU-LOG-SAME: actions=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY score=0
// GPU-LOG: actions=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PRESERVE|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY score=1
// GPU-LOG-NOT: FLATTEN
// GPU-LOG-NOT: ranked=not-enumerated

// UNK-LOG: hierarchy-global-cost ranked=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PRESERVE|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
// UNK-LOG-SAME: policy=cost-v04
// UNK-LOG: hierarchy-global-cost-schedule enumerated=yes truncated=no
// UNK-LOG-SAME: ranked-eq-default-3g=yes
// UNK-LOG-NOT: PREFETCH

// GPU-AN: storage-cost compiler-driven=yes
// GPU-AN: storage-cost ranked=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
// GPU-AN: storage-cost score=0
// GPU-AN: storage-cost enumerated=yes
// GPU-AN: storage-cost truncated=no
// GPU-AN: storage-cost ranked-eq-default-3g=yes
// GPU-AN: storage-cost argmin-size=1
// GPU-AN: storage-cost policy=cost-v04
// GPU-AN: note cost-ne-legality
// GPU-AN: note default-3g-frozen
// GPU-AN: note truncated-ne-ranked
// GPU-AN: note not-s2c2-argmin
// GPU-AN: cost=unchanged

// TRUNC: hierarchy-global-cost ranked=not-enumerated score=n/a policy=cost-v04
// TRUNC-SAME: note cost-does-not-rank-truncated-F
// TRUNC: hierarchy-global-cost-schedule enumerated=no truncated=yes
// TRUNC-SAME: argmin-size=n/a
// TRUNC-NOT: hierarchy-global-cost-candidate
// TRUNC-NOT: legal=64

// CUDA: s2c2-cuda-adapter storage-cost=1
// CUDA: s2c2-cuda-adapter storage-cost note cost-ranks-enumerated-F-only
// CUDA: s2c2-cuda-adapter storage-cost note cost-ne-legality
// CUDA: s2c2-cuda-adapter storage-cost policy=cost-v04
// CUDA: s2c2-cuda-adapter storage-cost note default-3g-frozen
// CUDA: s2c2-cuda-adapter storage-cost note truncated-ne-ranked
// CUDA: s2c2-cuda-adapter storage-cost note not-s2c2-argmin
// CUDA: s2c2-cuda-adapter storage-cost cost=unchanged

// ASCEND: s2c2-ascend-adapter storage-cost=1
// ASCEND: s2c2-ascend-adapter storage-cost note cost-ne-legality
// ASCEND: s2c2-ascend-adapter storage-cost policy=cost-v04
// ASCEND: s2c2-ascend-adapter storage-cost note default-3g-frozen
// ASCEND: s2c2-ascend-adapter storage-cost note truncated-ne-ranked
// ASCEND: s2c2-ascend-adapter storage-cost cost=unchanged

// EXCL: cannot combine

// LOWER: memref.copy
// LOWER-NOT: sched.wait
// LOWER-NOT: comm.stream

module {
}
