// RUN: s2c2-opt %s --s2c2-capability-schedule=device=rtx4090 --check-s2c2-execution 2>&1 | FileCheck %s --check-prefix=GPU
// RUN: s2c2-opt %s --s2c2-capability-schedule=device=npu-demo --check-s2c2-execution 2>&1 | FileCheck %s --check-prefix=NPU
// RUN: s2c2-opt %s --s2c2-capability-schedule=device=rtx4090 --profile=%S/../../docs/design/v3-dataset/v3-cap-schema-4090.jsonl --check-s2c2-execution 2>&1 | FileCheck %s --check-prefix=JSON

// Gated-MLP / SSD streaming case: same IR, two profiles, two schedules.
// 4090: keep load||compute; serialize SiLU||GEMM.
// NPU demo: keep both concurrent. Not Cost. Semantics unchanged.
module {
  // GPU-LABEL: func.func @ssd_stream_mlp
  // NPU-LABEL: func.func @ssd_stream_mlp
  // JSON-LABEL: func.func @ssd_stream_mlp
  // GPU: sched.concurrent
  // GPU: comm.stream
  // GPU: comp.gated_mlp
  // NPU: sched.concurrent
  // NPU: comm.stream
  // NPU: comp.gated_mlp
  // JSON: sched.concurrent
  // JSON: comp.gated_mlp
  func.func @ssd_stream_mlp(%x: tensor<1x8xf32>,
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

  // GPU: pair=C_silu||C_gemm
  // GPU: decision=serialize
  // NPU: pair=C_silu||C_gemm
  // NPU: decision=keep
  // GPU-LABEL: func.func @silu_and_gemm
  // NPU-LABEL: func.func @silu_and_gemm
  // GPU: sched.task
  // GPU: comp.elemwise
  // GPU: sched.task
  // GPU: comp.matmul
  // GPU-NOT: sched.concurrent
  // GPU-NOT: sched.wait
  // NPU: sched.concurrent
  // NPU: comp.elemwise
  // NPU: comp.matmul
  func.func @silu_and_gemm(%x: tensor<8xf32>, %w: tensor<8x8xf32>) {
    sched.concurrent {
      %ta = sched.task {
        %y = comp.elemwise %x {kind = #comp.elemwise<silu>} : tensor<8xf32> -> tensor<8xf32>
        sched.yield
      }
      %tb = sched.task {
        %z = comp.matmul %x, %w : tensor<8xf32>, tensor<8x8xf32> -> tensor<8xf32>
        sched.yield
      }
      sched.yield
    }
    return
  }
}
