// RUN: s2c2-opt %s --convert-s2c2-token-to-async --convert-s2c2-pipeline-to-async | FileCheck %s

// P1: StageOrder(S1, S2) is an await of S1 before S2's unpack.
module {
  // CHECK-LABEL: func.func @p1_stageorder_pack_then_unpack
  func.func @p1_stageorder_pack_then_unpack(%t: tensor<4xf32>) -> tensor<4xf32> {
    %w = stor.object : !stor.object<tensor<4xf32>>
    %hbm = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    // CHECK: %[[S1:.*]] = async.execute {
    // CHECK:   stor.pack
    // CHECK:   async.yield
    // CHECK: }
    // CHECK: async.await %[[S1]] : !async.token
    // CHECK: %[[S2:.*]] = async.execute {
    // CHECK:   stor.unpack
    // CHECK:   async.yield
    // CHECK: }
    // CHECK: async.await %[[S2]] : !async.token
    // CHECK: stor.unpack
    // CHECK-NOT: sched.pipeline
    // CHECK-NOT: sched.stage
    sched.pipeline {
      sched.stage "write" {
        stor.pack %t into %hbm : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
        sched.yield
      }
      sched.stage "read" {
        %v = stor.unpack %hbm : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
        sched.yield
      }
      sched.yield
    }
    %out = stor.unpack %hbm : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    return %out : tensor<4xf32>
  }
}
