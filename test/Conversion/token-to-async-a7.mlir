// RUN: s2c2-opt %s --convert-s2c2-token-to-async | FileCheck %s

// A7: A4 flatten candidate with task-local src/dst must NOT hoist the
// copy; fall back to outer execute + nested execute + await inner.
module {
  // CHECK-LABEL: func.func @a7_no_flatten_task_local
  func.func @a7_no_flatten_task_local() {
    // CHECK: %[[TASK:.*]] = async.execute {
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
    // CHECK: async.await %[[TASK]] : !async.token
    // CHECK-NOT: sched.wait
    // CHECK-NOT: comm.stream
    %task = sched.task {
      %obj = stor.object : !stor.object<tensor<4xf32>>
      %src = stor.materialize %obj : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, ssd>
      %dst = stor.materialize %obj : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
      %e = comm.stream %src, %dst : !stor.buffer<tensor<4xf32>, ssd>, !stor.buffer<tensor<4xf32>, hbm> -> !sched.token
      sched.yield
    }
    sched.wait %task : !sched.token
    return
  }
}
