// RUN: s2c2-opt %s --convert-s2c2-token-to-async --convert-s2c2-concurrent-to-async | FileCheck %s

// C1: sibling lexical order is not HB. No wait ⇒ no await.
module {
  // CHECK-LABEL: func.func @c1_no_sibling_hb
  func.func @c1_no_sibling_hb(%t: tensor<4xf32>) {
    %w = stor.object : !stor.object<tensor<4xf32>>
    %ssd = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, ssd>
    %hbm = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %t into %ssd : tensor<4xf32>, !stor.buffer<tensor<4xf32>, ssd>
    // CHECK: async.execute {
    // CHECK:   comm.copy
    // CHECK:   async.yield
    // CHECK: }
    // CHECK: async.execute {
    // CHECK:   stor.unpack
    // CHECK:   async.yield
    // CHECK: }
    // CHECK-NOT: async.await
    // CHECK-NOT: sched.concurrent
    // CHECK-NOT: sched.task
    // CHECK-NOT: sched.wait
    // CHECK-NOT: comm.stream
    sched.concurrent {
      %t1 = sched.task {
        %e = comm.stream %ssd, %hbm : !stor.buffer<tensor<4xf32>, ssd>, !stor.buffer<tensor<4xf32>, hbm> -> !sched.token
        sched.yield
      }
      %t2 = sched.task {
        %v = stor.unpack %hbm : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
        sched.yield
      }
      sched.yield
    }
    return
  }
}
