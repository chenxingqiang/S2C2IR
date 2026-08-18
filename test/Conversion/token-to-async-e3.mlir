// RUN: s2c2-opt %s --convert-s2c2-token-to-async | FileCheck %s

// E3: no wait ⇒ no await. Lowering must not invent sibling HB.
module {
  // CHECK-LABEL: func.func @e3_concurrent_no_wait
  func.func @e3_concurrent_no_wait(%t: tensor<4xf32>) {
    %w = stor.object : !stor.object<tensor<4xf32>>
    %ssd = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, ssd>
    %hbm = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %t into %ssd : tensor<4xf32>, !stor.buffer<tensor<4xf32>, ssd>
    // Producer stays a task (its token is not waited). Stream becomes
    // execute inside that task. No await is inserted.
    // CHECK: sched.task
    // CHECK: async.execute
    // CHECK: comm.copy
    // CHECK: sched.task
    // CHECK: stor.unpack
    // CHECK-NOT: async.await
    // CHECK-NOT: sched.wait
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
