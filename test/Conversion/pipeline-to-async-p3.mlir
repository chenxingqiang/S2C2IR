// RUN: s2c2-opt %s --convert-s2c2-token-to-async --convert-s2c2-pipeline-to-async | FileCheck %s

// P3: stage-local SSA is remapped inside that stage execute; S2 still
// awaits S1 (StageOrder).
module {
  // CHECK-LABEL: func.func @p3_stage_local_ssa
  func.func @p3_stage_local_ssa() {
    // CHECK: %[[S1:.*]] = async.execute {
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
    // CHECK: async.await %[[S1]] : !async.token
    // CHECK: %[[S2:.*]] = async.execute {
    // CHECK:   async.yield
    // CHECK: }
    // CHECK: async.await %[[S2]] : !async.token
    // CHECK-NOT: sched.pipeline
    // CHECK-NOT: sched.stage
    // CHECK-NOT: comm.stream
    sched.pipeline {
      sched.stage "xfer" {
        %obj = stor.object : !stor.object<tensor<4xf32>>
        %src = stor.materialize %obj : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, ssd>
        %dst = stor.materialize %obj : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
        %e = comm.stream %src, %dst : !stor.buffer<tensor<4xf32>, ssd>, !stor.buffer<tensor<4xf32>, hbm> -> !sched.token
        sched.yield
      }
      sched.stage "done" {
        sched.yield
      }
      sched.yield
    }
    return
  }
}
