// RUN: s2c2-opt %s --s2c2-evidence-bounded-schedule=profile=rtx4090 --check-s2c2-execution 2>&1 | grep -E 'evidence-bounded-schedule|capability-schedule' | FileCheck %s --check-prefix=GPU-LOG
// RUN: s2c2-opt %s --s2c2-evidence-bounded-schedule=profile=910B --check-s2c2-execution 2>&1 | grep -E 'evidence-bounded-schedule|capability-schedule' | FileCheck %s --check-prefix=NPU-LOG
// RUN: s2c2-opt %s --s2c2-evidence-bounded-schedule=profile=unknown --check-s2c2-execution 2>&1 | grep -E 'evidence-bounded-schedule|capability-schedule' | FileCheck %s --check-prefix=UNK-LOG
// RUN: s2c2-opt %s --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep evidence-bounded-schedule | FileCheck %s --check-prefix=CLI-LOG
// RUN: s2c2-opt %s --s2c2-evidence-bounded-schedule=profile=%S/../../docs/design/compiler-profiles/910B.json --check-s2c2-execution 2>&1 | grep evidence-bounded-schedule | FileCheck %s --check-prefix=JSON-LOG
// RUN: s2c2-opt %s --s2c2-evidence-bounded-schedule="profile=910B,evidence=%S/../../docs/design/v3-dataset/ascend910b/capability.jsonl" --check-s2c2-execution 2>&1 | grep -E 'evidence-bounded-schedule|capability-schedule' | FileCheck %s --check-prefix=CAT-LOG
// RUN: s2c2-opt %s --s2c2-evidence-bounded-schedule=profile=rtx4090 --check-s2c2-execution | FileCheck %s --check-prefix=GPU
// RUN: s2c2-opt %s --s2c2-evidence-bounded-schedule=profile=910B --check-s2c2-execution | FileCheck %s --check-prefix=NPU
// RUN: s2c2-opt %s --s2c2-evidence-bounded-schedule=profile=unknown --check-s2c2-execution | FileCheck %s --check-prefix=UNK
// RUN: s2c2-opt %s --s2c2-evidence-bounded-schedule=profile=%S/../../docs/design/compiler-profiles/910B-overlay.json --check-s2c2-execution | FileCheck %s --check-prefix=NPU

// Phase 3D: s2c2-opt named compiler profiles. Same MLIR, three profiles.
// rtx4090 serializes licensed C||C (16MiB and 128MiB) and HtoD||HtoD.
// 910B keeps 16MiB C||C, serializes 128MiB C||C, keeps HtoD||HtoD (no cell).
// unknown preserves every concurrent. --check-s2c2-execution after rewrite.
// Not Cost v0.4. Does not overwrite #69. Does not FileCheck microseconds.

// GPU-LOG: evidence-bounded-schedule profile=rtx4090
// GPU-LOG: rewrite=concurrent-to-serial
// GPU-LOG: pair=C||HtoD
// GPU-LOG: decision=keep
// GPU-LOG: pair=C||C relation=serial
// GPU-LOG: decision=serialize
// GPU-LOG: pair=C||C relation=serial
// GPU-LOG: decision=serialize
// GPU-LOG: pair=HtoD||HtoD relation=serial
// GPU-LOG: decision=serialize
// GPU-LOG: cost=unchanged

// NPU-LOG: evidence-bounded-schedule profile=910B
// NPU-LOG: pair=C||HtoD
// NPU-LOG: decision=keep
// NPU-LOG: pair=C||C relation=mixed
// NPU-LOG: rewrite_license=no
// NPU-LOG: decision=keep
// NPU-LOG: pair=C||C relation=serial
// NPU-LOG: rewrite_license=yes
// NPU-LOG: decision=serialize
// NPU-LOG: pair=HtoD||HtoD
// NPU-LOG: decision=keep
// NPU-LOG: cost=unchanged

// UNK-LOG: evidence-bounded-schedule profile=unknown
// UNK-LOG: decision=keep
// UNK-LOG: decision=keep
// UNK-LOG: decision=keep
// UNK-LOG: decision=keep
// UNK-LOG-NOT: decision=serialize
// UNK-LOG: cost=unchanged

// CLI-LOG: evidence-bounded-schedule profile=rtx4090
// CLI-LOG-SAME: evidence=builtin:rtx4090

// JSON-LOG: evidence-bounded-schedule profile=910B
// JSON-LOG-SAME: evidence=builtin:910B

// #69 catalog override: named 910B still does not invent a rewrite.
// CAT-LOG: evidence-bounded-schedule profile=910B
// CAT-LOG: pair=C||C relation=underdetermined
// CAT-LOG: decision=keep
// CAT-LOG: pair=C||C relation=underdetermined
// CAT-LOG: decision=keep
// CAT-LOG-NOT: decision=serialize
// CAT-LOG: cost=unchanged

module {
  // Prefetch || MLP is C||HtoD: keep on every named profile.
  // GPU-LABEL: func.func @prefetch_mlp
  // NPU-LABEL: func.func @prefetch_mlp
  // UNK-LABEL: func.func @prefetch_mlp
  // GPU: sched.concurrent
  // GPU: comm.stream
  // GPU: comp.gated_mlp
  // NPU: sched.concurrent
  // UNK: sched.concurrent
  func.func @prefetch_mlp(%x: tensor<1x8xf32>,
                          %w_t: tensor<8x8xf32>,
                          %wg: tensor<8x16xf32>,
                          %wu: tensor<8x16xf32>,
                          %wd: tensor<16x8xf32>) -> tensor<1x8xf32> {
    %w = stor.object : !stor.object<tensor<8x8xf32>>
    %ssd = stor.materialize %w : !stor.object<tensor<8x8xf32>> -> !stor.buffer<tensor<8x8xf32>, ssd>
    %hbm = stor.materialize %w : !stor.object<tensor<8x8xf32>> -> !stor.buffer<tensor<8x8xf32>, hbm>
    stor.pack %w_t into %ssd : tensor<8x8xf32>, !stor.buffer<tensor<8x8xf32>, ssd>
    %y = sched.concurrent -> tensor<1x8xf32> {
      %ts = sched.task {
        %t = comm.stream %ssd, %hbm : !stor.buffer<tensor<8x8xf32>, ssd>, !stor.buffer<tensor<8x8xf32>, hbm> -> !sched.token
        sched.yield
      }
      %tc, %out = sched.task -> tensor<1x8xf32> {
        %mlp = comp.gated_mlp %x, %wg, %wu, %wd {activation = #comp.activation<silu>}
          : tensor<1x8xf32>, tensor<8x16xf32>, tensor<8x16xf32>, tensor<16x8xf32>
            -> tensor<1x8xf32>
        sched.yield %mlp : tensor<1x8xf32>
      }
      sched.yield %out : tensor<1x8xf32>
    }
    return %y : tensor<1x8xf32>
  }

  // 16MiB C||C: 4090 serialize; 910B mixed keep; unknown keep.
  // GPU-LABEL: func.func @ffn_cc_16mib
  // GPU: sched.task
  // GPU: comp.elemwise
  // GPU-NOT: sched.concurrent
  // GPU-NOT: sched.wait
  // NPU-LABEL: func.func @ffn_cc_16mib
  // NPU: sched.concurrent
  // UNK-LABEL: func.func @ffn_cc_16mib
  // UNK: sched.concurrent
  func.func @ffn_cc_16mib(%x: tensor<4194304xf32>) {
    sched.concurrent {
      %ta = sched.task {
        %y = comp.elemwise %x {kind = #comp.elemwise<silu>} : tensor<4194304xf32> -> tensor<4194304xf32>
        sched.yield
      }
      %tb = sched.task {
        %z = comp.elemwise %x {kind = #comp.elemwise<silu>} : tensor<4194304xf32> -> tensor<4194304xf32>
        sched.yield
      }
      sched.yield
    }
    return
  }

  // 128MiB C||C: 4090 serialize; 910B serialize; unknown keep.
  // GPU-LABEL: func.func @ffn_cc_128mib
  // GPU: sched.task
  // GPU: comp.elemwise
  // GPU-NOT: sched.concurrent
  // GPU-NOT: sched.wait
  // NPU-LABEL: func.func @ffn_cc_128mib
  // NPU: sched.task
  // NPU: comp.elemwise
  // NPU-NOT: sched.concurrent
  // NPU-NOT: sched.wait
  // UNK-LABEL: func.func @ffn_cc_128mib
  // UNK: sched.concurrent
  func.func @ffn_cc_128mib(%x: tensor<33554432xf32>) {
    sched.concurrent {
      %ta = sched.task {
        %y = comp.elemwise %x {kind = #comp.elemwise<silu>} : tensor<33554432xf32> -> tensor<33554432xf32>
        sched.yield
      }
      %tb = sched.task {
        %z = comp.elemwise %x {kind = #comp.elemwise<silu>} : tensor<33554432xf32> -> tensor<33554432xf32>
        sched.yield
      }
      sched.yield
    }
    return
  }

  // Generic concurrent→serial is not C||C-specific: HtoD||HtoD on 4090
  // flattens; 910B/unknown have no licensed cell and keep.
  // GPU-LABEL: func.func @two_htod
  // GPU: comm.stream
  // GPU-NOT: sched.concurrent
  // GPU-NOT: sched.wait
  // NPU-LABEL: func.func @two_htod
  // NPU: sched.concurrent
  // UNK-LABEL: func.func @two_htod
  // UNK: sched.concurrent
  func.func @two_htod(%x: tensor<4194304xf32>) {
    %obj = stor.object : !stor.object<tensor<4194304xf32>>
    %host = stor.materialize %obj : !stor.object<tensor<4194304xf32>> -> !stor.buffer<tensor<4194304xf32>, host>
    %hbm0 = stor.materialize %obj : !stor.object<tensor<4194304xf32>> -> !stor.buffer<tensor<4194304xf32>, hbm>
    %hbm1 = stor.materialize %obj : !stor.object<tensor<4194304xf32>> -> !stor.buffer<tensor<4194304xf32>, hbm>
    stor.pack %x into %host : tensor<4194304xf32>, !stor.buffer<tensor<4194304xf32>, host>
    sched.concurrent {
      %ta = sched.task {
        %e0 = comm.stream %host, %hbm0 : !stor.buffer<tensor<4194304xf32>, host>, !stor.buffer<tensor<4194304xf32>, hbm> -> !sched.token
        sched.yield
      }
      %tb = sched.task {
        %e1 = comm.stream %host, %hbm1 : !stor.buffer<tensor<4194304xf32>, host>, !stor.buffer<tensor<4194304xf32>, hbm> -> !sched.token
        sched.yield
      }
      sched.yield
    }
    return
  }
}
