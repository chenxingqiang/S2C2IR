// RUN: s2c2-opt %s | s2c2-opt | FileCheck %s

module {
  // CHECK-LABEL: func.func @overlap_and_pipeline
  func.func @overlap_and_pipeline(%v: tensor<4xf32>) -> tensor<4xf32> {
    %src = stor.alloc : !stor.buffer<tensor<4xf32>, ssd>
    %dst = stor.alloc : !stor.buffer<tensor<4xf32>, hbm>
    %t = comm.stream %src, %dst : !stor.buffer<tensor<4xf32>, ssd>, !stor.buffer<tensor<4xf32>, hbm> -> !sched.token

    // CHECK: %[[Y:.*]] = sched.overlap -> tensor<4xf32> {
    // CHECK:   sched.wait %{{.*}} : !sched.token
    // CHECK:   sched.yield %{{.*}} : tensor<4xf32>
    // CHECK: } {
    // CHECK:   %{{.*}} = comm.stream
    // CHECK: }
    %y = sched.overlap -> tensor<4xf32> {
      sched.wait %t : !sched.token
      sched.yield %v : tensor<4xf32>
    } {
      %t2 = comm.stream %src, %dst : !stor.buffer<tensor<4xf32>, ssd>, !stor.buffer<tensor<4xf32>, hbm> -> !sched.token
      sched.yield
    }

    // CHECK: sched.pipeline {
    // CHECK:   sched.stage "prefetch" {
    // CHECK:   }
    // CHECK:   sched.stage "compute" {
    // CHECK:   }
    // CHECK: }
    sched.pipeline {
      sched.stage "prefetch" {
        sched.yield
      }
      sched.stage "compute" {
        sched.yield
      }
      sched.yield
    }
    return %y : tensor<4xf32>
  }

  // CHECK-LABEL: func.func @concurrent_tasks
  func.func @concurrent_tasks(%v: tensor<4xf32>) -> tensor<4xf32> {
    %w = stor.object : !stor.object<tensor<4xf32>>
    %ssd = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, ssd>
    %hbm = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %t = comm.stream %ssd, %hbm : !stor.buffer<tensor<4xf32>, ssd>, !stor.buffer<tensor<4xf32>, hbm> -> !sched.token

    // CHECK: %[[Y:.*]] = sched.concurrent -> tensor<4xf32> {
    // CHECK:   %[[TC:.*]], %[[OUT:.*]] = sched.task -> tensor<4xf32>
    // CHECK:   %[[TS:.*]] = sched.task
    // CHECK:   sched.yield %[[OUT]]
    %y = sched.concurrent -> tensor<4xf32> {
      %tc, %out = sched.task -> tensor<4xf32> {
        sched.wait %t : !sched.token
        sched.yield %v : tensor<4xf32>
      }
      %ts = sched.task {
        %t2 = comm.stream %ssd, %hbm : !stor.buffer<tensor<4xf32>, ssd>, !stor.buffer<tensor<4xf32>, hbm> -> !sched.token
        sched.yield
      }
      sched.yield %out : tensor<4xf32>
    }
    return %y : tensor<4xf32>
  }
}
