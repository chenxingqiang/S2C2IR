// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-storage-loop-contract | FileCheck %s --check-prefix=CONTRACT
// RUN: s2c2-opt %s --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-site|hierarchy-schedule|hierarchy-reuse|workload-candidate|loop-pipeline' | FileCheck %s --check-prefix=GPU-LOG
// RUN: s2c2-opt %s --profile=910B --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-schedule|hierarchy-reuse|loop-pipeline' | FileCheck %s --check-prefix=NPU-LOG
// RUN: s2c2-opt %s --profile=unknown --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-site|hierarchy-schedule|hierarchy-reuse|loop-pipeline' | FileCheck %s --check-prefix=UNK-LOG
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
// RUN: s2c2-cuda-adapter --dry-run --storage-loop 2>&1 | FileCheck %s --check-prefix=CUDA
// RUN: s2c2-ascend-adapter --dry-run --storage-loop 2>&1 | FileCheck %s --check-prefix=ASCEND
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-pipeline %S/../../docs/design/v3-dataset/storage-pipeline-4090.log | FileCheck %s --check-prefix=RT

// Phase 3I: scf.for storage pipeline + loop-carried residency.
// Prologue tile 0, then for i: compute(i) || prefetch(i+1), HtoD,
// consume. SSA iter_args are the double buffer. Next SSD is selected
// by scf.if on i+1 (object identity underdetermined). KEEP_RESIDENCY
// reuses a prologue replica across the loop only when proven.
// Inferred overlap authorizes PREFETCH only. Not Cost v0.4.

// CONTRACT: storage-loop compiler-driven=yes
// CONTRACT: inferred-overlap => prefetch-keep-only
// CONTRACT: note scf-for-software-pipeline
// CONTRACT: note ssa-iter-args-double-buffer
// CONTRACT: note loop-carried-lifetime
// CONTRACT: note proven-live-residency
// CONTRACT: note not-c-storage-flatten
// CONTRACT: note runtime-witness=storage-loop-wallclock
// CONTRACT: cost=unchanged
// CONTRACT-NOT: Cost v0.4
// CONTRACT-NOT: password

// GPU-LOG: workload-candidate #0 pair=C{{[|][|]}}Storage
// GPU-LOG-SAME: decision=KEEP
// GPU-LOG: hierarchy-site #5 op=stor.transfer src=ssd dst=host
// GPU-LOG-SAME: action=PREFETCH
// GPU-LOG-SAME: when=overlap
// GPU-LOG: hierarchy-site #7 op=stor.transfer src=ssd dst=host
// GPU-LOG-SAME: action=KEEP_RESIDENCY
// GPU-LOG: hierarchy-site #8 op=stor.transfer src=ssd dst=host
// GPU-LOG-SAME: action=KEEP_RESIDENCY
// GPU-LOG: hierarchy-site #9 op=stor.transfer src=host dst=hbm
// GPU-LOG-SAME: action=KEEP_RESIDENCY
// GPU-LOG: hierarchy-schedule sites=11 materialize=5 prefetch=1 transfer=2 keep-residency=3 preserve=0
// GPU-LOG: hierarchy-reuse applied=3
// GPU-LOG-SAME: skipped=0
// GPU-LOG-SAME: note proven-live-residency
// GPU-LOG: hierarchy-reuse note not-c-storage-flatten
// GPU-LOG: hierarchy-reuse note loop-carried-underdetermined
// GPU-LOG: loop-pipeline op=scf.for trip=2
// GPU-LOG-SAME: iter-args=1
// GPU-LOG-SAME: prefetch-sites=1
// GPU-LOG-SAME: consume-sites=1
// GPU-LOG-SAME: concurrent=1
// GPU-LOG: loop-pipeline loops=1
// GPU-LOG-SAME: note loop-carried-lifetime
// GPU-LOG-NOT: action=FLATTEN

// NPU-LOG: hierarchy-schedule sites=11 materialize=5 prefetch=1 transfer=2 keep-residency=3 preserve=0
// NPU-LOG: hierarchy-reuse applied=3
// NPU-LOG: loop-pipeline op=scf.for trip=2

// UNK-LOG: hierarchy-site #5
// UNK-LOG-SAME: action=PRESERVE
// UNK-LOG: hierarchy-schedule sites=11 materialize=5 prefetch=0 transfer=2 keep-residency=3 preserve=1
// UNK-LOG: hierarchy-reuse applied=3
// UNK-LOG: loop-pipeline loops=1
// UNK-LOG-NOT: action=PREFETCH
// UNK-LOG-NOT: action=FLATTEN

// GPU-AN: storage-hierarchy sites=11
// GPU-AN: storage-hierarchy prefetch=1
// GPU-AN: storage-hierarchy keep-residency=3
// GPU-AN: storage-hierarchy reuse-applied=3
// GPU-AN: note proven-live-residency
// GPU-AN: cost=unchanged
// GPU-AN-NOT: Cost v0.4

// UNK-AN: storage-hierarchy prefetch=0
// UNK-AN: storage-hierarchy preserve=1
// UNK-AN: storage-hierarchy reuse-applied=3

// GPU-N: 1
// UNK-N: 1
// GPU-XFER: 5

// CUDA: s2c2-cuda-adapter storage-loop=1
// CUDA: s2c2-cuda-adapter storage-loop note scf-for-software-pipeline
// CUDA: s2c2-cuda-adapter storage-loop note ssa-iter-args-double-buffer
// CUDA: s2c2-cuda-adapter storage-loop note loop-carried-lifetime
// CUDA: s2c2-cuda-adapter storage-loop note not-c-storage-flatten
// CUDA: s2c2-cuda-adapter storage-loop runtime-witness=storage-loop-wallclock
// CUDA: s2c2-cuda-adapter storage-loop cost=unchanged
// CUDA-NOT: Cost v0.4
// CUDA-NOT: password

// ASCEND: s2c2-ascend-adapter storage-loop=1
// ASCEND: s2c2-ascend-adapter storage-loop note loop-carried-lifetime
// ASCEND: s2c2-ascend-adapter storage-loop runtime-witness=storage-loop-wallclock
// ASCEND: s2c2-ascend-adapter storage-loop cost=unchanged

// RT: storage-pipeline measured=yes
// RT: cost=unchanged

module {
  // GPU-LABEL: func.func @ssd_loop_pipeline
  // UNK-LABEL: func.func @ssd_loop_pipeline
  // GPU: stor.materialize
  // GPU: scf.for
  // GPU: scf.if
  // GPU: sched.concurrent
  // GPU: comp.elemwise
  // GPU: stor.transfer
  // GPU-NOT: sched.wait
  // UNK: scf.for
  // UNK: sched.concurrent
  // UNK-NOT: sched.wait
  // LOWER-LABEL: func.func @ssd_loop_pipeline
  // LOWER: scf.for
  // LOWER: memref.copy
  // LOWER-NOT: sched.concurrent
  // LOWER-NOT: comm.stream
  // LOWER-NOT: sched.wait
  func.func @ssd_loop_pipeline(%tile0: tensor<4194304xf32>,
                               %tile1: tensor<4194304xf32>,
                               %tile2: tensor<4194304xf32>) -> tensor<4194304xf32> {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c2 = arith.constant 2 : index
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
    // for i: compute(current) || prefetch(next), then sequential HtoD.
    %y = scf.for %i = %c0 to %c2 step %c1 iter_args(%cur = %t0) -> (tensor<4194304xf32>) {
      %ip1 = arith.addi %i, %c1 : index
      %is1 = arith.cmpi eq, %ip1, %c1 : index
      %ssd_next = scf.if %is1 -> !stor.buffer<tensor<4194304xf32>, ssd> {
        scf.yield %ssd1 : !stor.buffer<tensor<4194304xf32>, ssd>
      } else {
        scf.yield %ssd2 : !stor.buffer<tensor<4194304xf32>, ssd>
      }
      %yout, %host_next = sched.concurrent -> tensor<4194304xf32>, !stor.buffer<tensor<4194304xf32>, host> {
        %tc, %out = sched.task -> tensor<4194304xf32> {
          %e = comp.elemwise %cur {kind = #comp.elemwise<silu>} : tensor<4194304xf32> -> tensor<4194304xf32>
          sched.yield %e : tensor<4194304xf32>
        }
        %tp, %hn = sched.task -> !stor.buffer<tensor<4194304xf32>, host> {
          %h = stor.transfer %ssd_next : !stor.buffer<tensor<4194304xf32>, ssd> -> !stor.buffer<tensor<4194304xf32>, host>
          sched.yield %h : !stor.buffer<tensor<4194304xf32>, host>
        }
        sched.yield %out, %hn : tensor<4194304xf32>, !stor.buffer<tensor<4194304xf32>, host>
      }
      %dev_next = stor.transfer %host_next : !stor.buffer<tensor<4194304xf32>, host> -> !stor.buffer<tensor<4194304xf32>, hbm>
      %t_next = stor.unpack %dev_next : !stor.buffer<tensor<4194304xf32>, hbm> -> tensor<4194304xf32>
      // Loop-invariant rematerialize temptation for tile 0 host.
      %host0_loop = stor.transfer %ssd0 : !stor.buffer<tensor<4194304xf32>, ssd> -> !stor.buffer<tensor<4194304xf32>, host>
      %keep_loop = stor.unpack %host0_loop : !stor.buffer<tensor<4194304xf32>, host> -> tensor<4194304xf32>
      scf.yield %t_next : tensor<4194304xf32>
    }
    // After loop: rematerialize tile 0 (proven same-block host + HBM).
    %host0b = stor.transfer %ssd0 : !stor.buffer<tensor<4194304xf32>, ssd> -> !stor.buffer<tensor<4194304xf32>, host>
    %dev0b = stor.transfer %host0b : !stor.buffer<tensor<4194304xf32>, host> -> !stor.buffer<tensor<4194304xf32>, hbm>
    %keep = stor.unpack %dev0b : !stor.buffer<tensor<4194304xf32>, hbm> -> tensor<4194304xf32>
    // Tile 1 through scf.if is underdetermined: first host for obj1.
    %host1b = stor.transfer %ssd1 : !stor.buffer<tensor<4194304xf32>, ssd> -> !stor.buffer<tensor<4194304xf32>, host>
    return %y : tensor<4194304xf32>
  }
}
