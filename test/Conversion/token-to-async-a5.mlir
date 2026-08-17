// RUN: s2c2-opt %s --convert-s2c2-token-to-async | FileCheck %s

// A5: inner stream wait must remap !sched.token → the inner execute token.
module {
  // CHECK-LABEL: func.func @a5_inner_stream_wait
  func.func @a5_inner_stream_wait(%t: tensor<4xf32>) {
    %w = stor.object : !stor.object<tensor<4xf32>>
    %ssd = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, ssd>
    %hbm = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %t into %ssd : tensor<4xf32>, !stor.buffer<tensor<4xf32>, ssd>
    // CHECK: %[[INNER:.*]] = async.execute {
    // CHECK:   comm.copy
    // CHECK:   async.yield
    // CHECK: }
    // CHECK: %[[TASK:.*]] = async.execute {
    // CHECK:   async.await %[[INNER]] : !async.token
    // CHECK:   async.yield
    // CHECK: }
    // CHECK: async.await %[[TASK]] : !async.token
    // CHECK-NOT: sched.wait
    // CHECK-NOT: comm.stream
    // CHECK-NOT: !sched.token
    %task = sched.task {
      %e = comm.stream %ssd, %hbm : !stor.buffer<tensor<4xf32>, ssd>, !stor.buffer<tensor<4xf32>, hbm> -> !sched.token
      sched.wait %e : !sched.token
      sched.yield
    }
    sched.wait %task : !sched.token
    return
  }
}
