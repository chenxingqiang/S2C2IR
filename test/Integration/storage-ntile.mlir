// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-storage-ntile-contract | FileCheck %s --check-prefix=CONTRACT
// RUN: s2c2-opt %s --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-site|hierarchy-schedule|hierarchy-reuse|workload-candidate' | FileCheck %s --check-prefix=GPU-LOG
// RUN: s2c2-opt %s --profile=910B --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-schedule|hierarchy-reuse' | FileCheck %s --check-prefix=NPU-LOG
// RUN: s2c2-opt %s --profile=unknown --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-site|hierarchy-schedule|hierarchy-reuse' | FileCheck %s --check-prefix=UNK-LOG
// RUN: s2c2-opt %s --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2> %t.gpu.err | FileCheck %s --check-prefix=GPU
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-hierarchy %t.gpu.err | FileCheck %s --check-prefix=GPU-AN
// RUN: s2c2-opt %s --profile=unknown --s2c2-evidence-bounded-schedule --check-s2c2-execution 2> %t.unk.err | FileCheck %s --check-prefix=UNK
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-hierarchy %t.unk.err | FileCheck %s --check-prefix=UNK-AN
// RUN: s2c2-opt %s --s2c2-evidence-bounded-schedule="profile=rtx4090 dump-schedule=%t.json" --check-s2c2-execution >/dev/null 2>&1
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-hierarchy %t.json | FileCheck %s --check-prefix=GPU-AN
// RUN: s2c2-opt %s --profile=rtx4090 --s2c2-evidence-bounded-schedule --s2c2-lower | FileCheck %s --check-prefix=LOWER
// RUN: s2c2-opt %s --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution | grep -c sched.concurrent | FileCheck %s --check-prefix=GPU-N
// RUN: s2c2-opt %s --profile=unknown --s2c2-evidence-bounded-schedule --check-s2c2-execution | grep -c sched.concurrent | FileCheck %s --check-prefix=UNK-N
// RUN: s2c2-opt %s --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution | grep -c stor.transfer | FileCheck %s --check-prefix=GPU-XFER
// RUN: s2c2-cuda-adapter --dry-run --storage-ntile 2>&1 | FileCheck %s --check-prefix=CUDA
// RUN: s2c2-ascend-adapter --dry-run --storage-ntile 2>&1 | FileCheck %s --check-prefix=ASCEND
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-pipeline %S/../../docs/design/v3-dataset/storage-pipeline-4090.log | FileCheck %s --check-prefix=RT

// Phase 3H: N-tile contract, N=3 unrolled realization + proven-safe
// residency reuse. Not an arbitrary-N / scf.for software pipeline.
// tile i compute || prefetch tile i+1, then sequential HtoD, then
// tile i+1 compute. KEEP_RESIDENCY reuses a live replica only when
// alias, dominance, type, and no intervening pack/dealloc are proven.
// Inferred overlap authorizes PREFETCH only. Not Cost v0.4.

// CONTRACT: storage-ntile compiler-driven=yes
// CONTRACT: inferred-overlap => prefetch-keep-only
// CONTRACT: note compute-then-prefetch-next
// CONTRACT: note proven-live-residency
// CONTRACT: note not-c-storage-flatten
// CONTRACT: cost=unchanged
// CONTRACT-NOT: Cost v0.4
// CONTRACT-NOT: password

// GPU-LOG: workload-candidate #0 pair=C{{[|][|]}}Storage
// GPU-LOG-SAME: decision=KEEP
// GPU-LOG: workload-candidate #1 pair=C{{[|][|]}}Storage
// GPU-LOG-SAME: decision=KEEP
// GPU-LOG: hierarchy-site #5 op=stor.transfer src=ssd dst=host
// GPU-LOG-SAME: action=PREFETCH
// GPU-LOG-SAME: when=overlap
// GPU-LOG: hierarchy-site #7 op=stor.transfer src=ssd dst=host
// GPU-LOG-SAME: action=PREFETCH
// GPU-LOG: hierarchy-site #9 op=stor.transfer src=ssd dst=host
// GPU-LOG-SAME: action=KEEP_RESIDENCY
// GPU-LOG: hierarchy-site #10 op=stor.transfer src=host dst=hbm
// GPU-LOG-SAME: action=KEEP_RESIDENCY
// GPU-LOG: hierarchy-schedule sites=11 materialize=4 prefetch=2 transfer=3 keep-residency=2 preserve=0
// GPU-LOG: hierarchy-reuse applied=2
// GPU-LOG-SAME: skipped=0
// GPU-LOG-SAME: note proven-live-residency
// GPU-LOG: hierarchy-reuse note not-c-storage-flatten
// GPU-LOG-NOT: action=FLATTEN

// NPU-LOG: hierarchy-schedule sites=11 materialize=4 prefetch=2 transfer=3 keep-residency=2 preserve=0
// NPU-LOG: hierarchy-reuse applied=2

// UNK-LOG: hierarchy-site #5
// UNK-LOG-SAME: action=PRESERVE
// UNK-LOG: hierarchy-site #7
// UNK-LOG-SAME: action=PRESERVE
// UNK-LOG: hierarchy-schedule sites=11 materialize=4 prefetch=0 transfer=3 keep-residency=2 preserve=2
// UNK-LOG: hierarchy-reuse applied=2
// UNK-LOG-NOT: action=PREFETCH
// UNK-LOG-NOT: action=FLATTEN

// GPU-AN: storage-hierarchy sites=11
// GPU-AN: storage-hierarchy prefetch=2
// GPU-AN: storage-hierarchy keep-residency=2
// GPU-AN: storage-hierarchy reuse-applied=2
// GPU-AN: note proven-live-residency
// GPU-AN: cost=unchanged
// GPU-AN-NOT: Cost v0.4

// UNK-AN: storage-hierarchy prefetch=0
// UNK-AN: storage-hierarchy preserve=2
// UNK-AN: storage-hierarchy reuse-applied=2

// GPU-N: 2
// UNK-N: 2
// GPU-XFER: 6

// CUDA: s2c2-cuda-adapter storage-ntile=1
// CUDA: s2c2-cuda-adapter storage-ntile note compute-then-prefetch-next
// CUDA: s2c2-cuda-adapter storage-ntile note proven-live-residency
// CUDA: s2c2-cuda-adapter storage-ntile note not-c-storage-flatten
// CUDA: s2c2-cuda-adapter storage-ntile cost=unchanged
// CUDA-NOT: Cost v0.4
// CUDA-NOT: password

// ASCEND: s2c2-ascend-adapter storage-ntile=1
// ASCEND: s2c2-ascend-adapter storage-ntile note proven-live-residency
// ASCEND: s2c2-ascend-adapter storage-ntile cost=unchanged

// RT: storage-pipeline measured=yes
// RT: cost=unchanged

module {
  // GPU-LABEL: func.func @ssd_ntile_pipeline
  // UNK-LABEL: func.func @ssd_ntile_pipeline
  // GPU: stor.materialize
  // GPU: sched.concurrent
  // GPU: comp.elemwise
  // GPU: stor.transfer
  // GPU: sched.concurrent
  // GPU-NOT: sched.wait
  // UNK: sched.concurrent
  // UNK: sched.concurrent
  // UNK-NOT: sched.wait
  // LOWER-LABEL: func.func @ssd_ntile_pipeline
  // LOWER: memref.copy
  // LOWER-NOT: sched.concurrent
  // LOWER-NOT: comm.stream
  func.func @ssd_ntile_pipeline(%tile0: tensor<4194304xf32>,
                                %tile1: tensor<4194304xf32>,
                                %tile2: tensor<4194304xf32>) -> tensor<4194304xf32> {
    %obj0 = stor.object : !stor.object<tensor<4194304xf32>>
    %obj1 = stor.object : !stor.object<tensor<4194304xf32>>
    %obj2 = stor.object : !stor.object<tensor<4194304xf32>>
    %ssd0 = stor.materialize %obj0 : !stor.object<tensor<4194304xf32>> -> !stor.buffer<tensor<4194304xf32>, ssd>
    %ssd1 = stor.materialize %obj1 : !stor.object<tensor<4194304xf32>> -> !stor.buffer<tensor<4194304xf32>, ssd>
    %ssd2 = stor.materialize %obj2 : !stor.object<tensor<4194304xf32>> -> !stor.buffer<tensor<4194304xf32>, ssd>
    stor.pack %tile0 into %ssd0 : tensor<4194304xf32>, !stor.buffer<tensor<4194304xf32>, ssd>
    stor.pack %tile1 into %ssd1 : tensor<4194304xf32>, !stor.buffer<tensor<4194304xf32>, ssd>
    stor.pack %tile2 into %ssd2 : tensor<4194304xf32>, !stor.buffer<tensor<4194304xf32>, ssd>
    // Prologue tile 0: eager SSD → Host → HBM, then consume.
    %host0 = stor.transfer %ssd0 : !stor.buffer<tensor<4194304xf32>, ssd> -> !stor.buffer<tensor<4194304xf32>, host>
    %dev0 = stor.transfer %host0 : !stor.buffer<tensor<4194304xf32>, host> -> !stor.buffer<tensor<4194304xf32>, hbm>
    %t0 = stor.unpack %dev0 : !stor.buffer<tensor<4194304xf32>, hbm> -> tensor<4194304xf32>
    // Compute tile 0 || prefetch tile 1 onto host.
    %y0, %host1 = sched.concurrent -> tensor<4194304xf32>, !stor.buffer<tensor<4194304xf32>, host> {
      %tc0, %out0 = sched.task -> tensor<4194304xf32> {
        %e0 = comp.elemwise %t0 {kind = #comp.elemwise<silu>} : tensor<4194304xf32> -> tensor<4194304xf32>
        sched.yield %e0 : tensor<4194304xf32>
      }
      %tp1, %h1 = sched.task -> !stor.buffer<tensor<4194304xf32>, host> {
        %h = stor.transfer %ssd1 : !stor.buffer<tensor<4194304xf32>, ssd> -> !stor.buffer<tensor<4194304xf32>, host>
        sched.yield %h : !stor.buffer<tensor<4194304xf32>, host>
      }
      sched.yield %out0, %h1 : tensor<4194304xf32>, !stor.buffer<tensor<4194304xf32>, host>
    }
    %dev1 = stor.transfer %host1 : !stor.buffer<tensor<4194304xf32>, host> -> !stor.buffer<tensor<4194304xf32>, hbm>
    %t1 = stor.unpack %dev1 : !stor.buffer<tensor<4194304xf32>, hbm> -> tensor<4194304xf32>
    // Compute tile 1 || prefetch tile 2 onto host.
    %y1, %host2 = sched.concurrent -> tensor<4194304xf32>, !stor.buffer<tensor<4194304xf32>, host> {
      %tc1, %out1 = sched.task -> tensor<4194304xf32> {
        %e1 = comp.elemwise %t1 {kind = #comp.elemwise<silu>} : tensor<4194304xf32> -> tensor<4194304xf32>
        sched.yield %e1 : tensor<4194304xf32>
      }
      %tp2, %h2 = sched.task -> !stor.buffer<tensor<4194304xf32>, host> {
        %h = stor.transfer %ssd2 : !stor.buffer<tensor<4194304xf32>, ssd> -> !stor.buffer<tensor<4194304xf32>, host>
        sched.yield %h : !stor.buffer<tensor<4194304xf32>, host>
      }
      sched.yield %out1, %h2 : tensor<4194304xf32>, !stor.buffer<tensor<4194304xf32>, host>
    }
    %dev2 = stor.transfer %host2 : !stor.buffer<tensor<4194304xf32>, host> -> !stor.buffer<tensor<4194304xf32>, hbm>
    %t2 = stor.unpack %dev2 : !stor.buffer<tensor<4194304xf32>, hbm> -> tensor<4194304xf32>
    %y2 = comp.elemwise %t2 {kind = #comp.elemwise<silu>} : tensor<4194304xf32> -> tensor<4194304xf32>
    // Rematerialize temptation for tile 1: live host and HBM already exist.
    %host1b = stor.transfer %ssd1 : !stor.buffer<tensor<4194304xf32>, ssd> -> !stor.buffer<tensor<4194304xf32>, host>
    %dev1b = stor.transfer %host1b : !stor.buffer<tensor<4194304xf32>, host> -> !stor.buffer<tensor<4194304xf32>, hbm>
    %keep = stor.unpack %dev1b : !stor.buffer<tensor<4194304xf32>, hbm> -> tensor<4194304xf32>
    return %y2 : tensor<4194304xf32>
  }
}
