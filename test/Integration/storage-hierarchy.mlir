// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-storage-hierarchy-contract | FileCheck %s --check-prefix=CONTRACT
// RUN: s2c2-opt %s --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-site|hierarchy-schedule|workload-candidate' | FileCheck %s --check-prefix=GPU-LOG
// RUN: s2c2-opt %s --profile=910B --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-site|hierarchy-schedule' | FileCheck %s --check-prefix=NPU-LOG
// RUN: s2c2-opt %s --profile=unknown --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-site|hierarchy-schedule' | FileCheck %s --check-prefix=UNK-LOG
// RUN: s2c2-opt %s --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | FileCheck %s --check-prefix=GPU-PRETTY
// RUN: s2c2-opt %s --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2> %t.gpu.err | FileCheck %s --check-prefix=GPU
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-hierarchy %t.gpu.err | FileCheck %s --check-prefix=GPU-AN
// RUN: s2c2-opt %s --profile=910B --s2c2-evidence-bounded-schedule --check-s2c2-execution 2> %t.npu.err | FileCheck %s --check-prefix=NPU
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-hierarchy %t.npu.err | FileCheck %s --check-prefix=NPU-AN
// RUN: s2c2-opt %s --profile=unknown --s2c2-evidence-bounded-schedule --check-s2c2-execution 2> %t.unk.err | FileCheck %s --check-prefix=UNK
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-hierarchy %t.unk.err | FileCheck %s --check-prefix=UNK-AN
// RUN: s2c2-opt %s --s2c2-evidence-bounded-schedule="profile=rtx4090 dump-schedule=%t.json" --check-s2c2-execution >/dev/null 2>&1
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-hierarchy %t.json | FileCheck %s --check-prefix=GPU-AN
// RUN: s2c2-opt %s --profile=rtx4090 --s2c2-evidence-bounded-schedule --s2c2-lower | FileCheck %s --check-prefix=LOWER
// RUN: s2c2-opt %s --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution | grep -c sched.concurrent | FileCheck %s --check-prefix=GPU-N
// RUN: s2c2-opt %s --profile=unknown --s2c2-evidence-bounded-schedule --check-s2c2-execution | grep -c sched.concurrent | FileCheck %s --check-prefix=UNK-N
// RUN: s2c2-opt %s --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep hierarchy-reuse | FileCheck %s --check-prefix=REUSE
// RUN: s2c2-opt %s --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution | grep -c stor.transfer | FileCheck %s --check-prefix=GPU-XFER
// RUN: s2c2-cuda-adapter --dry-run --storage-hierarchy 2>&1 | FileCheck %s --check-prefix=CUDA
// RUN: s2c2-ascend-adapter --dry-run --storage-hierarchy 2>&1 | FileCheck %s --check-prefix=ASCEND
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-pipeline %S/../../docs/design/v3-dataset/storage-pipeline-4090.log | FileCheck %s --check-prefix=RT

// Phase 3G: storage hierarchy scheduling. IR is semantic only.
// Compiler decides when to materialize / prefetch / transfer / keep
// residency. Inferred C||Storage overlap authorizes PREFETCH (KEEP)
// only. KEEP_RESIDENCY reuse applies only when a live replica is
// proven safe. Not C||Storage flatten.
// Not Cost v0.4. No new Capability grid. Do not FileCheck microseconds.

// CONTRACT: storage-hierarchy compiler-driven=yes
// CONTRACT: no-evidence => no-destructive-optimization
// CONTRACT: inferred-overlap => prefetch-keep-only
// CONTRACT: note ssd-host-hbm-compute
// CONTRACT: note keep-residency-ne-rematerialize
// CONTRACT: note inferred-overlap-ne-flatten
// CONTRACT: cost=unchanged
// CONTRACT-NOT: Cost v0.4
// CONTRACT-NOT: password

// GPU-LOG: workload-candidate #0 pair=C||Storage
// GPU-LOG-SAME: decision=KEEP
// GPU-LOG: hierarchy-site #0 op=stor.materialize
// GPU-LOG-SAME: action=MATERIALIZE
// GPU-LOG-SAME: reason=object-residency
// GPU-LOG: hierarchy-site #1 op=stor.materialize
// GPU-LOG-SAME: action=MATERIALIZE
// GPU-LOG: hierarchy-site #2 op=stor.transfer src=ssd dst=host
// GPU-LOG-SAME: action=MATERIALIZE
// GPU-LOG-SAME: when=eager
// GPU-LOG-SAME: reason=first-host-residency
// GPU-LOG: hierarchy-site #3 op=stor.transfer src=host dst=hbm
// GPU-LOG-SAME: action=TRANSFER
// GPU-LOG-SAME: when=sequential
// GPU-LOG: hierarchy-site #4 op=stor.transfer src=ssd dst=host
// GPU-LOG-SAME: pair=C{{[|][|]}}Storage
// GPU-LOG-SAME: action=PREFETCH
// GPU-LOG-SAME: when=overlap
// GPU-LOG-SAME: reason=storage-communication-overlap
// GPU-LOG: hierarchy-site #5 op=stor.transfer src=host dst=hbm
// GPU-LOG-SAME: action=TRANSFER
// GPU-LOG: hierarchy-site #6 op=stor.transfer src=ssd dst=host
// GPU-LOG-SAME: action=KEEP_RESIDENCY
// GPU-LOG-SAME: reason=live-host-residency
// GPU-LOG: hierarchy-site #7 op=stor.transfer src=host dst=hbm
// GPU-LOG-SAME: action=KEEP_RESIDENCY
// GPU-LOG-SAME: reason=live-device-residency
// GPU-LOG: hierarchy-schedule sites=8 materialize=3 prefetch=1 transfer=2 keep-residency=2 preserve=0
// GPU-LOG-NOT: action=FLATTEN

// GPU-PRETTY: hierarchy-site #4 : stor.transfer ssd -> host
// GPU-PRETTY-NEXT:     action   : PREFETCH
// GPU-PRETTY-NEXT:     when     : overlap
// GPU-PRETTY: hierarchy-site #6 : stor.transfer ssd -> host
// GPU-PRETTY-NEXT:     action   : KEEP_RESIDENCY
// GPU-PRETTY: hierarchy-schedule sites=8

// NPU-LOG: hierarchy-site #4
// NPU-LOG-SAME: action=PREFETCH
// NPU-LOG: hierarchy-site #6
// NPU-LOG-SAME: action=KEEP_RESIDENCY
// NPU-LOG: hierarchy-schedule sites=8 materialize=3 prefetch=1 transfer=2 keep-residency=2 preserve=0

// UNK-LOG: hierarchy-site #4
// UNK-LOG-SAME: action=PRESERVE
// UNK-LOG-SAME: reason=no-evidence
// UNK-LOG: hierarchy-site #6
// UNK-LOG-SAME: action=KEEP_RESIDENCY
// UNK-LOG: hierarchy-schedule sites=8 materialize=3 prefetch=0 transfer=2 keep-residency=2 preserve=1
// UNK-LOG-NOT: action=PREFETCH
// UNK-LOG-NOT: action=FLATTEN

// GPU-AN: storage-hierarchy compiler-driven=yes
// GPU-AN: storage-hierarchy sites=8
// GPU-AN: storage-hierarchy materialize=3
// GPU-AN: storage-hierarchy prefetch=1
// GPU-AN: storage-hierarchy transfer=2
// GPU-AN: storage-hierarchy keep-residency=2
// GPU-AN: storage-hierarchy preserve=0
// GPU-AN: note keep-residency-ne-rematerialize
// GPU-AN: note inferred-overlap-ne-flatten
// GPU-AN: storage-hierarchy reuse-applied=2
// GPU-AN: cost=unchanged
// GPU-AN-NOT: Cost v0.4

// NPU-AN: storage-hierarchy prefetch=1
// NPU-AN: storage-hierarchy keep-residency=2
// NPU-AN: storage-hierarchy preserve=0

// UNK-AN: storage-hierarchy prefetch=0
// UNK-AN: storage-hierarchy keep-residency=2
// UNK-AN: storage-hierarchy preserve=1

// GPU-N: 1
// UNK-N: 1
// GPU-XFER: 4
// REUSE: hierarchy-reuse applied=2
// REUSE: hierarchy-reuse note proven-live-residency
// REUSE: hierarchy-reuse note not-c-storage-flatten
// REUSE-NOT: sched.wait

// CUDA: s2c2-cuda-adapter storage-hierarchy=1
// CUDA: s2c2-cuda-adapter storage-hierarchy note ssd-host-hbm-compute
// CUDA: s2c2-cuda-adapter storage-hierarchy note inferred-overlap-ne-flatten
// CUDA: s2c2-cuda-adapter storage-hierarchy note keep-residency-ne-rematerialize
// CUDA: s2c2-cuda-adapter storage-hierarchy runtime-witness=storage-pipeline
// CUDA: s2c2-cuda-adapter storage-hierarchy cost=unchanged
// CUDA-NOT: Cost v0.4
// CUDA-NOT: password

// ASCEND: s2c2-ascend-adapter storage-hierarchy=1
// ASCEND: s2c2-ascend-adapter storage-hierarchy note ssd-host-hbm-compute
// ASCEND: s2c2-ascend-adapter storage-hierarchy note inferred-overlap-ne-flatten
// ASCEND: s2c2-ascend-adapter storage-hierarchy cost=unchanged

// RT: storage-pipeline measured=yes
// RT: cost=unchanged

module {
  // GPU-LABEL: func.func @ssd_hierarchy_lifetime
  // NPU-LABEL: func.func @ssd_hierarchy_lifetime
  // UNK-LABEL: func.func @ssd_hierarchy_lifetime
  // GPU: stor.materialize
  // GPU: stor.transfer
  // GPU: sched.concurrent
  // GPU: stor.transfer
  // GPU-NOT: sched.wait
  // NPU-NOT: sched.wait
  // UNK: sched.concurrent
  // UNK-NOT: sched.wait
  // LOWER-LABEL: func.func @ssd_hierarchy_lifetime
  // LOWER: memref.copy
  // LOWER: linalg.matmul
  // LOWER-NOT: sched.concurrent
  // LOWER-NOT: comm.stream
  // LOWER-NOT: comp.gated_mlp
  func.func @ssd_hierarchy_lifetime(%x: tensor<1x8xf32>,
                                    %wg: tensor<8x16xf32>,
                                    %wu: tensor<8x16xf32>,
                                    %wd: tensor<16x8xf32>,
                                    %tile0: tensor<4194304xf32>,
                                    %tile1: tensor<4194304xf32>) -> tensor<1x8xf32> {
    %obj0 = stor.object : !stor.object<tensor<4194304xf32>>
    %obj1 = stor.object : !stor.object<tensor<4194304xf32>>
    %ssd0 = stor.materialize %obj0 : !stor.object<tensor<4194304xf32>> -> !stor.buffer<tensor<4194304xf32>, ssd>
    %ssd1 = stor.materialize %obj1 : !stor.object<tensor<4194304xf32>> -> !stor.buffer<tensor<4194304xf32>, ssd>
    stor.pack %tile0 into %ssd0 : tensor<4194304xf32>, !stor.buffer<tensor<4194304xf32>, ssd>
    stor.pack %tile1 into %ssd1 : tensor<4194304xf32>, !stor.buffer<tensor<4194304xf32>, ssd>
    // Eager prologue: first host + device residency of tile 0.
    %host0 = stor.transfer %ssd0 : !stor.buffer<tensor<4194304xf32>, ssd> -> !stor.buffer<tensor<4194304xf32>, host>
    %dev0 = stor.transfer %host0 : !stor.buffer<tensor<4194304xf32>, host> -> !stor.buffer<tensor<4194304xf32>, hbm>
    // Prefetch tile 1 onto host beside independent compute.
    %y, %host1 = sched.concurrent -> tensor<1x8xf32>, !stor.buffer<tensor<4194304xf32>, host> {
      %tc, %out = sched.task -> tensor<1x8xf32> {
        %mlp = comp.gated_mlp %x, %wg, %wu, %wd {activation = #comp.activation<silu>}
          : tensor<1x8xf32>, tensor<8x16xf32>, tensor<8x16xf32>, tensor<16x8xf32>
            -> tensor<1x8xf32>
        sched.yield %mlp : tensor<1x8xf32>
      }
      %ts, %h1 = sched.task -> !stor.buffer<tensor<4194304xf32>, host> {
        %h = stor.transfer %ssd1 : !stor.buffer<tensor<4194304xf32>, ssd> -> !stor.buffer<tensor<4194304xf32>, host>
        sched.yield %h : !stor.buffer<tensor<4194304xf32>, host>
      }
      sched.yield %out, %h1 : tensor<1x8xf32>, !stor.buffer<tensor<4194304xf32>, host>
    }
    // Consume the live host residency. Do not rematerialize from SSD.
    %dev1 = stor.transfer %host1 : !stor.buffer<tensor<4194304xf32>, host> -> !stor.buffer<tensor<4194304xf32>, hbm>
    // Rematerialize temptation: same object already has host and HBM.
    %host1b = stor.transfer %ssd1 : !stor.buffer<tensor<4194304xf32>, ssd> -> !stor.buffer<tensor<4194304xf32>, host>
    %dev1b = stor.transfer %host1b : !stor.buffer<tensor<4194304xf32>, host> -> !stor.buffer<tensor<4194304xf32>, hbm>
    %keep_host = stor.unpack %dev1 : !stor.buffer<tensor<4194304xf32>, hbm> -> tensor<4194304xf32>
    %keep_dev = stor.unpack %dev1b : !stor.buffer<tensor<4194304xf32>, hbm> -> tensor<4194304xf32>
    return %y : tensor<1x8xf32>
  }
}
