// RUN: s2c2-opt %s --check-s2c2-execution | FileCheck %s

// E6: pipeline stages are HB-ordered by construct (S1 →HB S2).
//
//   S1.pack --StageOrder/HB--> S2.unpack   => defined
module {
  // CHECK-LABEL: func.func @e6_pipeline_stages
  func.func @e6_pipeline_stages(%t: tensor<4xf32>) -> tensor<4xf32> {
    %w = stor.object : !stor.object<tensor<4xf32>>
    %hbm = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
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
