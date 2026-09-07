// RUN: s2c2-opt %s --check-s2c2-execution | FileCheck %s

// E2: stream completion event establishes Valid(dest).
module {
  // CHECK-LABEL: func.func @e2_stream_wait_unpack
  func.func @e2_stream_wait_unpack(%t: tensor<4xf32>) -> tensor<4xf32> {
    %w = stor.object : !stor.object<tensor<4xf32>>
    %ssd = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, ssd>
    %hbm = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %t into %ssd : tensor<4xf32>, !stor.buffer<tensor<4xf32>, ssd>
    %e = comm.stream %ssd, %hbm : !stor.buffer<tensor<4xf32>, ssd>, !stor.buffer<tensor<4xf32>, hbm> -> !sched.token
    sched.wait %e : !sched.token
    %v = stor.unpack %hbm : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    return %v : tensor<4xf32>
  }
}
