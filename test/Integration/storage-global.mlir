// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-storage-global-contract | FileCheck %s --check-prefix=CONTRACT
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global|hierarchy-global-schedule' | FileCheck %s --check-prefix=GPU-LOG
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=unknown --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global|hierarchy-global-schedule' | FileCheck %s --check-prefix=UNK-LOG
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2> %t.gpu.err
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-global %t.gpu.err | FileCheck %s --check-prefix=GPU-AN
// RUN: s2c2-opt %S/storage-hierarchy.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 dump-schedule=%t.json" --check-s2c2-execution >/dev/null 2>&1
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-global %t.json | FileCheck %s --check-prefix=GPU-AN
// RUN: s2c2-opt %s --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global' | FileCheck %s --check-prefix=TRUNC
// RUN: s2c2-opt %s --profile=unknown --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global' | FileCheck %s --check-prefix=TRUNC
// RUN: s2c2-opt %s --s2c2-evidence-bounded-schedule="profile=rtx4090 dump-schedule=%t.trunc.json" --check-s2c2-execution >/dev/null 2>&1
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-global %t.trunc.json | FileCheck %s --check-prefix=TRUNC-AN
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --s2c2-lower | FileCheck %s --check-prefix=LOWER
// RUN: s2c2-cuda-adapter --dry-run --storage-global 2>&1 | FileCheck %s --check-prefix=CUDA
// RUN: s2c2-ascend-adapter --dry-run --storage-global 2>&1 | FileCheck %s --check-prefix=ASCEND
// RUN: not s2c2-cuda-adapter --dry-run --storage-global --storage-joint 2>&1 | FileCheck %s --check-prefix=EXCL

// Phase 4C: F(program) as the product of frozen F(chain).
// product <= 64 enumerates the complete set. product > 64 does
// not construct F(program) and must not report legal=64.
// default-3g selects the historical tuple or fails. Chain
// definition is frozen. Cost does not rank or license.
// No C||Storage flatten. Not Cost v0.4. Do not FileCheck microseconds.

// CONTRACT: storage-global compiler-driven=yes
// CONTRACT: no-evidence => no-destructive-optimization
// CONTRACT: note global-candidates-then-select
// CONTRACT: note selection-ne-cost
// CONTRACT: note policy=default-3g
// CONTRACT: note default-3g-frozen
// CONTRACT: note chain-def-frozen
// CONTRACT: note cost-ranking-is-policy-cost-v04
// CONTRACT: note truncated-ne-complete-F
// CONTRACT: note historical-tuple-or-fail
// CONTRACT: cost=unchanged
// CONTRACT-NOT: Cost v0.4
// CONTRACT-NOT: password

// GPU-LOG: hierarchy-global selected=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
// GPU-LOG-SAME: enumerated=yes
// GPU-LOG-SAME: truncated=no
// GPU-LOG-SAME: legal=8
// GPU-LOG-SAME: policy=default-3g
// GPU-LOG-SAME: note default-3g-frozen
// GPU-LOG-SAME: note chain-def-frozen
// GPU-LOG: hierarchy-global-schedule chains=4 product=8 enumerated=yes truncated=no legal=8
// GPU-LOG-SAME: selected-in-legal=yes
// GPU-LOG: hierarchy-global-candidate
// GPU-LOG-SAME: actions=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
// GPU-LOG-NOT: FLATTEN
// GPU-LOG-NOT: legal=not-enumerated

// UNK-LOG: hierarchy-global selected=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PRESERVE|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
// UNK-LOG-SAME: enumerated=yes
// UNK-LOG-SAME: truncated=no
// UNK-LOG-SAME: legal=4
// UNK-LOG: hierarchy-global-schedule chains=4 product=4 enumerated=yes truncated=no legal=4
// UNK-LOG-SAME: selected-in-legal=yes
// UNK-LOG-NOT: PREFETCH

// GPU-AN: storage-global compiler-driven=yes
// GPU-AN: storage-global chains=4
// GPU-AN: storage-global product=8
// GPU-AN: storage-global enumerated=yes
// GPU-AN: storage-global truncated=no
// GPU-AN: storage-global legal=8
// GPU-AN: storage-global selected-in-legal=yes
// GPU-AN: storage-global policy=default-3g
// GPU-AN: note selection-ne-cost
// GPU-AN: note chain-def-frozen
// GPU-AN: note truncated-ne-complete-F
// GPU-AN: note historical-tuple-or-fail
// GPU-AN: cost=unchanged
// GPU-AN-NOT: Cost v0.4

// Seven sequential rematerialize chains: |F(chain)|=2 each, product=128.
// Must not silently publish legal=64 as F(program).
// TRUNC: hierarchy-global-schedule chains=7 product=128 enumerated=no truncated=yes legal=not-enumerated
// TRUNC-SAME: selected-in-legal=yes
// TRUNC-NOT: hierarchy-global-candidate
// TRUNC-NOT: legal=64
// TRUNC-NOT: hierarchy-global-error

// TRUNC-AN: storage-global chains=7
// TRUNC-AN: storage-global product=128
// TRUNC-AN: storage-global enumerated=no
// TRUNC-AN: storage-global truncated=yes
// TRUNC-AN: storage-global legal=not-enumerated
// TRUNC-AN: storage-global selected-in-legal=yes
// TRUNC-AN-NOT: legal=64

// CUDA: s2c2-cuda-adapter storage-global=1
// CUDA: s2c2-cuda-adapter storage-global note global-candidates-then-select
// CUDA: s2c2-cuda-adapter storage-global note selection-ne-cost
// CUDA: s2c2-cuda-adapter storage-global policy=default-3g
// CUDA: s2c2-cuda-adapter storage-global note chain-def-frozen
// CUDA: s2c2-cuda-adapter storage-global note truncated-ne-complete-F
// CUDA: s2c2-cuda-adapter storage-global note historical-tuple-or-fail
// CUDA: s2c2-cuda-adapter storage-global cost=unchanged
// CUDA-NOT: Cost v0.4

// ASCEND: s2c2-ascend-adapter storage-global=1
// ASCEND: s2c2-ascend-adapter storage-global note selection-ne-cost
// ASCEND: s2c2-ascend-adapter storage-global policy=default-3g
// ASCEND: s2c2-ascend-adapter storage-global note chain-def-frozen
// ASCEND: s2c2-ascend-adapter storage-global note truncated-ne-complete-F
// ASCEND: s2c2-ascend-adapter storage-global note historical-tuple-or-fail
// ASCEND: s2c2-ascend-adapter storage-global cost=unchanged

// EXCL: cannot combine

// LOWER: memref.copy
// LOWER-NOT: sched.wait
// LOWER-NOT: comm.stream

module {
  func.func @seven_binary_chains(%tile: tensor<8xf32>) {
    %o0 = stor.object : !stor.object<tensor<8xf32>>
    %s0 = stor.materialize %o0 : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, ssd>
    stor.pack %tile into %s0 : tensor<8xf32>, !stor.buffer<tensor<8xf32>, ssd>
    %h0 = stor.transfer %s0 : !stor.buffer<tensor<8xf32>, ssd> -> !stor.buffer<tensor<8xf32>, host>
    %d0 = stor.transfer %h0 : !stor.buffer<tensor<8xf32>, host> -> !stor.buffer<tensor<8xf32>, hbm>
    %r0 = stor.transfer %s0 : !stor.buffer<tensor<8xf32>, ssd> -> !stor.buffer<tensor<8xf32>, host>
    %o1 = stor.object : !stor.object<tensor<8xf32>>
    %s1 = stor.materialize %o1 : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, ssd>
    stor.pack %tile into %s1 : tensor<8xf32>, !stor.buffer<tensor<8xf32>, ssd>
    %h1 = stor.transfer %s1 : !stor.buffer<tensor<8xf32>, ssd> -> !stor.buffer<tensor<8xf32>, host>
    %d1 = stor.transfer %h1 : !stor.buffer<tensor<8xf32>, host> -> !stor.buffer<tensor<8xf32>, hbm>
    %r1 = stor.transfer %s1 : !stor.buffer<tensor<8xf32>, ssd> -> !stor.buffer<tensor<8xf32>, host>
    %o2 = stor.object : !stor.object<tensor<8xf32>>
    %s2 = stor.materialize %o2 : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, ssd>
    stor.pack %tile into %s2 : tensor<8xf32>, !stor.buffer<tensor<8xf32>, ssd>
    %h2 = stor.transfer %s2 : !stor.buffer<tensor<8xf32>, ssd> -> !stor.buffer<tensor<8xf32>, host>
    %d2 = stor.transfer %h2 : !stor.buffer<tensor<8xf32>, host> -> !stor.buffer<tensor<8xf32>, hbm>
    %r2 = stor.transfer %s2 : !stor.buffer<tensor<8xf32>, ssd> -> !stor.buffer<tensor<8xf32>, host>
    %o3 = stor.object : !stor.object<tensor<8xf32>>
    %s3 = stor.materialize %o3 : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, ssd>
    stor.pack %tile into %s3 : tensor<8xf32>, !stor.buffer<tensor<8xf32>, ssd>
    %h3 = stor.transfer %s3 : !stor.buffer<tensor<8xf32>, ssd> -> !stor.buffer<tensor<8xf32>, host>
    %d3 = stor.transfer %h3 : !stor.buffer<tensor<8xf32>, host> -> !stor.buffer<tensor<8xf32>, hbm>
    %r3 = stor.transfer %s3 : !stor.buffer<tensor<8xf32>, ssd> -> !stor.buffer<tensor<8xf32>, host>
    %o4 = stor.object : !stor.object<tensor<8xf32>>
    %s4 = stor.materialize %o4 : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, ssd>
    stor.pack %tile into %s4 : tensor<8xf32>, !stor.buffer<tensor<8xf32>, ssd>
    %h4 = stor.transfer %s4 : !stor.buffer<tensor<8xf32>, ssd> -> !stor.buffer<tensor<8xf32>, host>
    %d4 = stor.transfer %h4 : !stor.buffer<tensor<8xf32>, host> -> !stor.buffer<tensor<8xf32>, hbm>
    %r4 = stor.transfer %s4 : !stor.buffer<tensor<8xf32>, ssd> -> !stor.buffer<tensor<8xf32>, host>
    %o5 = stor.object : !stor.object<tensor<8xf32>>
    %s5 = stor.materialize %o5 : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, ssd>
    stor.pack %tile into %s5 : tensor<8xf32>, !stor.buffer<tensor<8xf32>, ssd>
    %h5 = stor.transfer %s5 : !stor.buffer<tensor<8xf32>, ssd> -> !stor.buffer<tensor<8xf32>, host>
    %d5 = stor.transfer %h5 : !stor.buffer<tensor<8xf32>, host> -> !stor.buffer<tensor<8xf32>, hbm>
    %r5 = stor.transfer %s5 : !stor.buffer<tensor<8xf32>, ssd> -> !stor.buffer<tensor<8xf32>, host>
    %o6 = stor.object : !stor.object<tensor<8xf32>>
    %s6 = stor.materialize %o6 : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, ssd>
    stor.pack %tile into %s6 : tensor<8xf32>, !stor.buffer<tensor<8xf32>, ssd>
    %h6 = stor.transfer %s6 : !stor.buffer<tensor<8xf32>, ssd> -> !stor.buffer<tensor<8xf32>, host>
    %d6 = stor.transfer %h6 : !stor.buffer<tensor<8xf32>, host> -> !stor.buffer<tensor<8xf32>, hbm>
    %r6 = stor.transfer %s6 : !stor.buffer<tensor<8xf32>, ssd> -> !stor.buffer<tensor<8xf32>, host>
    return
  }
}
