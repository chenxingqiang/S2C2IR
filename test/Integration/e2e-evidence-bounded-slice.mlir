// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-e2e-contract | FileCheck %s --check-prefix=CONTRACT
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-e2e-gain %S/../../docs/design/v3-dataset/ascend910b/cc-rewrite.log | FileCheck %s --check-prefix=GAIN
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=rtx4090 profile=%S/../../docs/design/v3-dataset/v3-cap-schema-4090.jsonl" --check-s2c2-execution 2>&1 | grep capability-schedule | FileCheck %s --check-prefix=GPU-LOG
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=ascend910b:ascend profile=%S/../../docs/design/v3-dataset/ascend910b/cc-size-applicability.jsonl" --check-s2c2-execution 2>&1 | grep capability-schedule | FileCheck %s --check-prefix=OV-LOG
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=ascend910b:ascend profile=%S/../../docs/design/v3-dataset/ascend910b/capability.jsonl" --check-s2c2-execution 2>&1 | grep capability-schedule | FileCheck %s --check-prefix=CAT-LOG
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=rtx4090 profile=%S/../../docs/design/v3-dataset/v3-cap-schema-4090.jsonl" --check-s2c2-execution | FileCheck %s --check-prefix=GPU
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=ascend910b:ascend profile=%S/../../docs/design/v3-dataset/ascend910b/cc-size-applicability.jsonl" --check-s2c2-execution | FileCheck %s --check-prefix=OV
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=ascend910b:ascend profile=%S/../../docs/design/v3-dataset/ascend910b/capability.jsonl" --check-s2c2-execution | FileCheck %s --check-prefix=CAT
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=rtx4090 profile=%S/../../docs/design/v3-dataset/v3-cap-schema-4090.jsonl" --s2c2-lower | FileCheck %s --check-prefix=LOWER

// End-to-end evidence-bounded slice: SSD prefetch || Gated MLP, then
// C||C at 16MiB and 128MiB. Same IR, 4090 vs 910B overlay vs #69.
// No sibling wait. Not Cost. Do not FileCheck microseconds.

// CONTRACT: e2e evidence-bounded-schedule
// CONTRACT: no-evidence => no-destructive-optimization
// CONTRACT: invariant semantic-ne-perf-serial
// CONTRACT: invariant capability-ne-rewrite
// CONTRACT: invariant scoped-ne-global
// CONTRACT: invariant underdetermined-preserve
// CONTRACT: invariant rewrite-preserves-hb
// CONTRACT: slice ssd-prefetch||gated-mlp||C||C
// CONTRACT: cost=unchanged
// CONTRACT-NOT: Cost v0.4
// CONTRACT-NOT: password

// Licensed C||C stage measurement is T_seq/T_par, not Cost.
// GAIN: e2e-slice pair=C||C band=128MiB..512MiB
// GAIN: n-grid=32M,64M,128M
// GAIN: relations=serial
// GAIN: rewrite_license=yes
// GAIN: t-opt-over-base-defined=yes
// GAIN: note t-opt-is-t-seq
// GAIN: note t-base-is-t-par
// GAIN: note 32M-outlier-not-cost
// GAIN: note not-cost-v04
// GAIN: cost=unchanged
// GAIN-NOT: Cost v0.4
// GAIN-NOT: password

// Prefetch || MLP is C||HtoD: keep on every catalog.
// GPU-LOG: pair=C||HtoD
// GPU-LOG: decision=keep
// GPU-LOG: pair=C||C relation=serial
// GPU-LOG: decision=serialize
// GPU-LOG: pair=C||C relation=serial
// GPU-LOG: decision=serialize
// GPU-LOG: cost=unchanged

// OV-LOG: pair=C||HtoD
// OV-LOG: decision=keep
// OV-LOG: pair=C||C relation=mixed
// OV-LOG: rewrite_license=no
// OV-LOG: decision=keep
// OV-LOG: pair=C||C relation=serial
// OV-LOG: rewrite_license=yes
// OV-LOG: decision=serialize
// OV-LOG: cost=unchanged

// CAT-LOG: pair=C||HtoD
// CAT-LOG: decision=keep
// CAT-LOG: pair=C||C relation=underdetermined
// CAT-LOG: decision=keep
// CAT-LOG: pair=C||C relation=underdetermined
// CAT-LOG: decision=keep
// CAT-LOG-NOT: decision=serialize
// CAT-LOG: cost=unchanged

module {
  // GPU-LABEL: func.func @prefetch_mlp
  // OV-LABEL: func.func @prefetch_mlp
  // CAT-LABEL: func.func @prefetch_mlp
  // GPU: sched.concurrent
  // GPU: comm.stream
  // GPU: comp.gated_mlp
  // OV: sched.concurrent
  // OV: comm.stream
  // OV: comp.gated_mlp
  // CAT: sched.concurrent
  // CAT: comm.stream
  // CAT: comp.gated_mlp
  // LOWER-LABEL: func.func @prefetch_mlp
  // LOWER: memref.copy
  // LOWER: linalg.matmul
  // LOWER-NOT: sched.concurrent
  // LOWER-NOT: comm.stream
  // LOWER-NOT: comp.gated_mlp
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

  // 16MiB: 4090 serializes; overlay mixed keeps; #69 keeps.
  // GPU-LABEL: func.func @ffn_cc_16mib
  // GPU: sched.task
  // GPU: comp.elemwise
  // GPU-NOT: sched.concurrent
  // GPU-NOT: sched.wait
  // OV-LABEL: func.func @ffn_cc_16mib
  // OV: sched.concurrent
  // CAT-LABEL: func.func @ffn_cc_16mib
  // CAT: sched.concurrent
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

  // 128MiB: 4090 and overlay serialize; #69 keeps.
  // GPU-LABEL: func.func @ffn_cc_128mib
  // GPU: sched.task
  // GPU: comp.elemwise
  // GPU-NOT: sched.concurrent
  // GPU-NOT: sched.wait
  // OV-LABEL: func.func @ffn_cc_128mib
  // OV: sched.task
  // OV: comp.elemwise
  // OV-NOT: sched.concurrent
  // OV-NOT: sched.wait
  // CAT-LABEL: func.func @ffn_cc_128mib
  // CAT: sched.concurrent
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
}
