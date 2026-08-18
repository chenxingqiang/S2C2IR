// RUN: s2c2-opt %s --convert-s2c2-token-to-async | FileCheck %s

// A6: stream src/dst defined inside the task must be remapped into the
// nested execute (not left as stale outer-task SSA).
module {
  // CHECK-LABEL: func.func @a6_task_local_operands
  func.func @a6_task_local_operands(%t: tensor<4xf32>) {
    // CHECK: %[[TASK:.*]] = async.execute {
    // CHECK:   %[[OBJ:.*]] = stor.object
    // CHECK:   %[[SSD:.*]] = stor.materialize %[[OBJ]]
    // CHECK:   %[[HBM:.*]] = stor.materialize %[[OBJ]]
    // CHECK:   stor.pack
    // CHECK:   %[[INNER:.*]] = async.execute {
    // CHECK:     comm.copy %[[SSD]], %[[HBM]]
    // CHECK:     async.yield
    // CHECK:   }
    // CHECK:   async.await %[[INNER]] : !async.token
    // CHECK:   async.yield
    // CHECK: }
    // CHECK: async.await %[[TASK]] : !async.token
    // CHECK-NOT: sched.wait
    // CHECK-NOT: comm.stream
    %task = sched.task {
      %obj = stor.object : !stor.object<tensor<4xf32>>
      %src = stor.materialize %obj : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, ssd>
      %dst = stor.materialize %obj : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
      stor.pack %t into %src : tensor<4xf32>, !stor.buffer<tensor<4xf32>, ssd>
      %e = comm.stream %src, %dst : !stor.buffer<tensor<4xf32>, ssd>, !stor.buffer<tensor<4xf32>, hbm> -> !sched.token
      sched.wait %e : !sched.token
      sched.yield
    }
    sched.wait %task : !sched.token
    return
  }
}
