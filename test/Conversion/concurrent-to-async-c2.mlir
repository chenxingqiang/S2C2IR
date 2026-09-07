// RUN: s2c2-opt %s --convert-s2c2-token-to-async --convert-s2c2-concurrent-to-async | FileCheck %s

// C2: each concurrent sibling remaps its own task-local SSA.
module {
  // CHECK-LABEL: func.func @c2_per_task_local_ssa
  func.func @c2_per_task_local_ssa() {
    // CHECK: async.execute {
    // CHECK:   %[[OBJ:.*]] = stor.object
    // CHECK:   %[[SSD:.*]] = stor.materialize %[[OBJ]]
    // CHECK:   %[[HBM:.*]] = stor.materialize %[[OBJ]]
    // CHECK:   %[[INNER:.*]] = async.execute {
    // CHECK:     comm.copy %[[SSD]], %[[HBM]]
    // CHECK:     async.yield
    // CHECK:   }
    // CHECK:   async.await %[[INNER]] : !async.token
    // CHECK:   async.yield
    // CHECK: }
    // CHECK: async.execute {
    // CHECK:   %[[OBJ2:.*]] = stor.object
    // CHECK:   %[[BUF:.*]] = stor.materialize %[[OBJ2]]
    // CHECK:   stor.unpack %[[BUF]]
    // CHECK:   async.yield
    // CHECK: }
    // CHECK-NOT: sched.concurrent
    // CHECK-NOT: sched.task
    // CHECK-NOT: sched.wait
    // CHECK-NOT: comm.stream
    sched.concurrent {
      %ta = sched.task {
        %obj = stor.object : !stor.object<tensor<4xf32>>
        %src = stor.materialize %obj : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, ssd>
        %dst = stor.materialize %obj : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
        %e = comm.stream %src, %dst : !stor.buffer<tensor<4xf32>, ssd>, !stor.buffer<tensor<4xf32>, hbm> -> !sched.token
        sched.yield
      }
      %tb = sched.task {
        %obj = stor.object : !stor.object<tensor<4xf32>>
        %buf = stor.materialize %obj : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
        %v = stor.unpack %buf : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
        sched.yield
      }
      sched.yield
    }
    return
  }
}
