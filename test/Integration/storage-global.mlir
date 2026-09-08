// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-storage-global-contract | FileCheck %s --check-prefix=CONTRACT
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global|hierarchy-global-schedule' | FileCheck %s --check-prefix=GPU-LOG
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=unknown --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global|hierarchy-global-schedule' | FileCheck %s --check-prefix=UNK-LOG
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2> %t.gpu.err
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-global %t.gpu.err | FileCheck %s --check-prefix=GPU-AN
// RUN: s2c2-opt %S/storage-hierarchy.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 dump-schedule=%t.json" --check-s2c2-execution >/dev/null 2>&1
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-global %t.json | FileCheck %s --check-prefix=GPU-AN
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --s2c2-lower | FileCheck %s --check-prefix=LOWER
// RUN: s2c2-cuda-adapter --dry-run --storage-global 2>&1 | FileCheck %s --check-prefix=CUDA
// RUN: s2c2-ascend-adapter --dry-run --storage-global 2>&1 | FileCheck %s --check-prefix=ASCEND
// RUN: not s2c2-cuda-adapter --dry-run --storage-global --storage-joint 2>&1 | FileCheck %s --check-prefix=EXCL

// Phase 4C: F(program) as the product of frozen F(chain).
// default-3g selects the historical tuple. Chain definition is
// frozen. Cost does not rank or license. No C||Storage flatten.
// Not Cost v0.4. Do not FileCheck microseconds.

// CONTRACT: storage-global compiler-driven=yes
// CONTRACT: no-evidence => no-destructive-optimization
// CONTRACT: note global-candidates-then-select
// CONTRACT: note selection-ne-cost
// CONTRACT: note policy=default-3g
// CONTRACT: note default-3g-frozen
// CONTRACT: note chain-def-frozen
// CONTRACT: note cost-ranking-is-policy-cost-v04
// CONTRACT: cost=unchanged
// CONTRACT-NOT: Cost v0.4
// CONTRACT-NOT: password

// GPU-LOG: hierarchy-global selected=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
// GPU-LOG-SAME: legal=8
// GPU-LOG-SAME: policy=default-3g
// GPU-LOG-SAME: note default-3g-frozen
// GPU-LOG-SAME: note chain-def-frozen
// GPU-LOG: hierarchy-global-schedule chains=4 legal=8
// GPU-LOG-SAME: selected-in-legal=yes
// GPU-LOG: hierarchy-global-candidate
// GPU-LOG-SAME: actions=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
// GPU-LOG-NOT: FLATTEN

// UNK-LOG: hierarchy-global selected=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PRESERVE|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
// UNK-LOG-SAME: legal=4
// UNK-LOG: hierarchy-global-schedule chains=4 legal=4
// UNK-LOG-SAME: selected-in-legal=yes
// UNK-LOG-NOT: PREFETCH

// GPU-AN: storage-global compiler-driven=yes
// GPU-AN: storage-global chains=4
// GPU-AN: storage-global legal=8
// GPU-AN: storage-global selected-in-legal=yes
// GPU-AN: storage-global policy=default-3g
// GPU-AN: note selection-ne-cost
// GPU-AN: note chain-def-frozen
// GPU-AN: cost=unchanged
// GPU-AN-NOT: Cost v0.4

// CUDA: s2c2-cuda-adapter storage-global=1
// CUDA: s2c2-cuda-adapter storage-global note global-candidates-then-select
// CUDA: s2c2-cuda-adapter storage-global note selection-ne-cost
// CUDA: s2c2-cuda-adapter storage-global policy=default-3g
// CUDA: s2c2-cuda-adapter storage-global note chain-def-frozen
// CUDA: s2c2-cuda-adapter storage-global cost=unchanged
// CUDA-NOT: Cost v0.4

// ASCEND: s2c2-ascend-adapter storage-global=1
// ASCEND: s2c2-ascend-adapter storage-global note selection-ne-cost
// ASCEND: s2c2-ascend-adapter storage-global policy=default-3g
// ASCEND: s2c2-ascend-adapter storage-global note chain-def-frozen
// ASCEND: s2c2-ascend-adapter storage-global cost=unchanged

// EXCL: cannot combine

// LOWER: memref.copy
// LOWER-NOT: sched.wait
// LOWER-NOT: comm.stream

module {
}
