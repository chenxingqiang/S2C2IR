// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-storage-schedule-contract | FileCheck %s --check-prefix=CONTRACT
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-candidates|hierarchy-schedule' | FileCheck %s --check-prefix=GPU-LOG
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=unknown --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-candidates|hierarchy-schedule' | FileCheck %s --check-prefix=UNK-LOG
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2> %t.gpu.err
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-schedule %t.gpu.err | FileCheck %s --check-prefix=GPU-AN
// RUN: s2c2-opt %S/storage-hierarchy.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 dump-schedule=%t.json" --check-s2c2-execution >/dev/null 2>&1
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-schedule %t.json | FileCheck %s --check-prefix=GPU-AN
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --s2c2-lower | FileCheck %s --check-prefix=LOWER
// RUN: s2c2-cuda-adapter --dry-run --storage-schedule 2>&1 | FileCheck %s --check-prefix=CUDA
// RUN: s2c2-ascend-adapter --dry-run --storage-schedule 2>&1 | FileCheck %s --check-prefix=ASCEND
// RUN: not s2c2-cuda-adapter --dry-run --storage-schedule --storage-hierarchy 2>&1 | FileCheck %s --check-prefix=EXCL

// Phase 4A: legal storage action set F(site), then select the
// default-3G inhabitant. Cost does not rank or license.
// PREFETCH vs PRESERVE is the overlap choice. KEEP_RESIDENCY vs
// TRANSFER is the rematerialize choice. No C||Storage flatten.
// Not Cost v0.4. Do not FileCheck microseconds.

// CONTRACT: storage-schedule compiler-driven=yes
// CONTRACT: no-evidence => no-destructive-optimization
// CONTRACT: note legal-candidates-then-select
// CONTRACT: note selection-ne-cost
// CONTRACT: note selection-ne-rewrite-license
// CONTRACT: note policy=default-3g
// CONTRACT: note not-c-storage-flatten
// CONTRACT: cost=unchanged
// CONTRACT-NOT: Cost v0.4
// CONTRACT-NOT: password

// GPU-LOG: hierarchy-candidates #4 legal=PREFETCH,PRESERVE selected=PREFETCH
// GPU-LOG-SAME: policy=default-3g
// GPU-LOG: hierarchy-candidates #6 legal=KEEP_RESIDENCY,TRANSFER selected=KEEP_RESIDENCY
// GPU-LOG: hierarchy-candidates #7 legal=KEEP_RESIDENCY,TRANSFER selected=KEEP_RESIDENCY
// GPU-LOG: hierarchy-schedule sites=8
// GPU-LOG-SAME: multi-candidate=3
// GPU-LOG-SAME: selected-in-legal=yes
// GPU-LOG-SAME: policy=default-3g
// GPU-LOG-SAME: note selection-ne-cost
// GPU-LOG-NOT: FLATTEN

// UNK-LOG: hierarchy-candidates #4 legal=PRESERVE selected=PRESERVE
// UNK-LOG: hierarchy-candidates #6 legal=KEEP_RESIDENCY,TRANSFER selected=KEEP_RESIDENCY
// UNK-LOG: hierarchy-schedule
// UNK-LOG-SAME: multi-candidate=2
// UNK-LOG-SAME: selected-in-legal=yes

// GPU-AN: storage-schedule compiler-driven=yes
// GPU-AN: storage-schedule sites=8
// GPU-AN: storage-schedule multi-candidate=3
// GPU-AN: storage-schedule selected-in-legal=yes
// GPU-AN: storage-schedule policy=default-3g
// GPU-AN: note selection-ne-cost
// GPU-AN: note selection-ne-rewrite-license
// GPU-AN: cost=unchanged
// GPU-AN-NOT: Cost v0.4

// CUDA: s2c2-cuda-adapter storage-schedule=1
// CUDA: s2c2-cuda-adapter storage-schedule note legal-candidates-then-select
// CUDA: s2c2-cuda-adapter storage-schedule note selection-ne-cost
// CUDA: s2c2-cuda-adapter storage-schedule policy=default-3g
// CUDA: s2c2-cuda-adapter storage-schedule cost=unchanged
// CUDA-NOT: Cost v0.4

// ASCEND: s2c2-ascend-adapter storage-schedule=1
// ASCEND: s2c2-ascend-adapter storage-schedule note selection-ne-cost
// ASCEND: s2c2-ascend-adapter storage-schedule policy=default-3g
// ASCEND: s2c2-ascend-adapter storage-schedule cost=unchanged

// EXCL: cannot combine

// LOWER: memref.copy
// LOWER-NOT: sched.wait
// LOWER-NOT: comm.stream

module {
}
