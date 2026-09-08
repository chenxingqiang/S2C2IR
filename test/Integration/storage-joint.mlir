// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-storage-joint-contract | FileCheck %s --check-prefix=CONTRACT
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-joint|hierarchy-joint-schedule' | FileCheck %s --check-prefix=GPU-LOG
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=unknown --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-joint|hierarchy-joint-schedule' | FileCheck %s --check-prefix=UNK-LOG
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2> %t.gpu.err
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-joint %t.gpu.err | FileCheck %s --check-prefix=GPU-AN
// RUN: s2c2-opt %S/storage-hierarchy.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 dump-schedule=%t.json" --check-s2c2-execution >/dev/null 2>&1
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-joint %t.json | FileCheck %s --check-prefix=GPU-AN
// RUN: s2c2-opt %s --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-joint|hierarchy-joint-schedule' | FileCheck %s --check-prefix=ABA
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --s2c2-lower | FileCheck %s --check-prefix=LOWER
// RUN: s2c2-cuda-adapter --dry-run --storage-joint 2>&1 | FileCheck %s --check-prefix=CUDA
// RUN: s2c2-ascend-adapter --dry-run --storage-joint 2>&1 | FileCheck %s --check-prefix=ASCEND
// RUN: not s2c2-cuda-adapter --dry-run --storage-joint --storage-schedule 2>&1 | FileCheck %s --check-prefix=EXCL

// Phase 4B: joint F(chain) over consecutive sites of one object.
// A chain is a maximal contiguous run in program order.
// Interleaved objects split the chain; same object later is a new
// chain, not a splice. default-3g selects the historical 3G tuple
// and is frozen. Cost does not rank or license. No C||Storage flatten.
// Not Cost v0.4. Do not FileCheck microseconds.

// CONTRACT: storage-joint compiler-driven=yes
// CONTRACT: no-evidence => no-destructive-optimization
// CONTRACT: note joint-candidates-then-select
// CONTRACT: note selection-ne-cost
// CONTRACT: note selection-ne-rewrite-license
// CONTRACT: note policy=default-3g
// CONTRACT: note default-3g-frozen
// CONTRACT: note cost-ranking-is-policy-cost-v04
// CONTRACT: note not-c-storage-flatten
// CONTRACT: cost=unchanged
// CONTRACT-NOT: Cost v0.4
// CONTRACT-NOT: password

// GPU-LOG: hierarchy-joint #0 object=0 sites=0 legal=1
// GPU-LOG-SAME: selected=MATERIALIZE
// GPU-LOG: hierarchy-joint #1 object=1 sites=1 legal=1
// GPU-LOG-SAME: selected=MATERIALIZE
// GPU-LOG: hierarchy-joint #2 object=0 sites=2,3 legal=1
// GPU-LOG-SAME: selected=MATERIALIZE|TRANSFER
// GPU-LOG: hierarchy-joint #3 object=1 sites=4,5,6,7 legal=8
// GPU-LOG-SAME: selected=PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
// GPU-LOG-SAME: policy=default-3g
// GPU-LOG-SAME: note default-3g-frozen
// GPU-LOG: hierarchy-joint-candidate #3
// GPU-LOG-SAME: actions=PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
// GPU-LOG: hierarchy-joint-schedule chains=4 legal=8
// GPU-LOG-SAME: selected-in-legal=yes
// GPU-LOG-SAME: policy=default-3g
// GPU-LOG-SAME: note selection-ne-cost
// GPU-LOG-NOT: sites=0,2,3
// GPU-LOG-NOT: sites=1,4,5,6,7
// GPU-LOG-NOT: FLATTEN

// UNK-LOG: hierarchy-joint #3 object=1 sites=4,5,6,7 legal=4
// UNK-LOG-SAME: selected=PRESERVE|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
// UNK-LOG: hierarchy-joint-schedule
// UNK-LOG-SAME: chains=4 legal=4
// UNK-LOG-SAME: selected-in-legal=yes
// UNK-LOG-NOT: PREFETCH
// UNK-LOG-NOT: sites=1,4,5,6,7

// GPU-AN: storage-joint compiler-driven=yes
// GPU-AN: storage-joint chains=4
// GPU-AN: storage-joint legal=8
// GPU-AN: storage-joint selected-in-legal=yes
// GPU-AN: storage-joint policy=default-3g
// GPU-AN: note selection-ne-cost
// GPU-AN: note default-3g-frozen
// GPU-AN: cost=unchanged
// GPU-AN-NOT: Cost v0.4

// ABA-NOT: sites=0,2
// ABA: hierarchy-joint #0 object=0 sites=0 legal=1
// ABA: hierarchy-joint #1 object=1 sites=1 legal=1
// ABA: hierarchy-joint #2 object=0 sites=2 legal=1
// ABA: hierarchy-joint-schedule chains=3

// CUDA: s2c2-cuda-adapter storage-joint=1
// CUDA: s2c2-cuda-adapter storage-joint note joint-candidates-then-select
// CUDA: s2c2-cuda-adapter storage-joint note selection-ne-cost
// CUDA: s2c2-cuda-adapter storage-joint policy=default-3g
// CUDA: s2c2-cuda-adapter storage-joint note default-3g-frozen
// CUDA: s2c2-cuda-adapter storage-joint cost=unchanged
// CUDA-NOT: Cost v0.4

// ASCEND: s2c2-ascend-adapter storage-joint=1
// ASCEND: s2c2-ascend-adapter storage-joint note selection-ne-cost
// ASCEND: s2c2-ascend-adapter storage-joint policy=default-3g
// ASCEND: s2c2-ascend-adapter storage-joint note default-3g-frozen
// ASCEND: s2c2-ascend-adapter storage-joint cost=unchanged

// EXCL: cannot combine

// LOWER: memref.copy
// LOWER-NOT: sched.wait
// LOWER-NOT: comm.stream

module {
  func.func @interleave_objects(%tileA: tensor<8xf32>, %tileB: tensor<8xf32>) {
    %objA = stor.object : !stor.object<tensor<8xf32>>
    %objB = stor.object : !stor.object<tensor<8xf32>>
    %ssdA = stor.materialize %objA : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, ssd>
    %ssdB = stor.materialize %objB : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, ssd>
    stor.pack %tileA into %ssdA : tensor<8xf32>, !stor.buffer<tensor<8xf32>, ssd>
    stor.pack %tileB into %ssdB : tensor<8xf32>, !stor.buffer<tensor<8xf32>, ssd>
    %hostA = stor.transfer %ssdA : !stor.buffer<tensor<8xf32>, ssd> -> !stor.buffer<tensor<8xf32>, host>
    return
  }
}
