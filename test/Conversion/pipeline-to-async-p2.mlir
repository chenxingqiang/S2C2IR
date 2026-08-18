// RUN: s2c2-opt %s --convert-s2c2-token-to-async --convert-s2c2-pipeline-to-async | FileCheck %s

// P2: three stages; each successor awaits the predecessor. Not unordered
// sibling executes.
module {
  // CHECK-LABEL: func.func @p2_chained_three_stages
  func.func @p2_chained_three_stages(%t: tensor<4xf32>) {
    %w = stor.object : !stor.object<tensor<4xf32>>
    %hbm = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    // CHECK: %[[S1:.*]] = async.execute
    // CHECK: async.await %[[S1]] : !async.token
    // CHECK: %[[S2:.*]] = async.execute
    // CHECK: async.await %[[S2]] : !async.token
    // CHECK: %[[S3:.*]] = async.execute
    // CHECK: async.await %[[S3]] : !async.token
    // CHECK-NOT: sched.pipeline
    // CHECK-NOT: sched.stage
    sched.pipeline {
      sched.stage "s1" {
        stor.pack %t into %hbm : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
        sched.yield
      }
      sched.stage "s2" {
        %v = stor.unpack %hbm : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
        sched.yield
      }
      sched.stage "s3" {
        %v = stor.unpack %hbm : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
        sched.yield
      }
      sched.yield
    }
    return
  }
}
