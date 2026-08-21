// RUN: s2c2-opt %s --convert-s2c2-token-to-async --convert-s2c2-concurrent-to-async --convert-s2c2-pipeline-to-async | FileCheck %s

// X1 (lowered): Token SW, StageOrder, and Concurrent siblings compose.
// Prefetch await is before S1. S1 is awaited before S2. Inside S2 the
// compute and communication executes are launched without an await
// between them; both tokens are joined at stage completion.
module {
  // CHECK-LABEL: func.func @compose_token_pipeline_concurrent
  func.func @compose_token_pipeline_concurrent(%t: tensor<4xf32>) -> tensor<4xf32> {
    %w_obj = stor.object : !stor.object<tensor<4xf32>>
    %a_obj = stor.object : !stor.object<tensor<4xf32>>
    %w_ssd = stor.materialize %w_obj : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, ssd>
    %w_hbm = stor.materialize %w_obj : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %a_hbm = stor.materialize %a_obj : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %a_ssd = stor.materialize %a_obj : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, ssd>

    stor.pack %t into %w_ssd : tensor<4xf32>, !stor.buffer<tensor<4xf32>, ssd>
    // CHECK: %[[PRE:.*]] = async.execute {
    // CHECK:   comm.copy
    // CHECK:   async.yield
    // CHECK: }
    // CHECK: async.await %[[PRE]] : !async.token
    // CHECK: %[[S1:.*]] = async.execute {
    // CHECK:   stor.pack
    // CHECK:   async.yield
    // CHECK: }
    // CHECK: async.await %[[S1]] : !async.token
    // CHECK: %[[S2:.*]] = async.execute {
    // CHECK:   %[[COMP:.*]] = async.execute {
    // CHECK:     stor.unpack
    // CHECK:     stor.unpack
    // CHECK:     comp.elemwise
    // CHECK:     async.yield
    // CHECK:   }
    // No sibling HB: launch Communication before awaiting Compute.
    // CHECK-NOT: async.await
    // CHECK:   %[[COMM:.*]] = async.execute {
    // CHECK:     comm.copy
    // CHECK:     async.yield
    // CHECK:   }
    // CHECK:   async.await %[[COMP]] : !async.token
    // CHECK:   async.await %[[COMM]] : !async.token
    // CHECK:   async.yield
    // CHECK: }
    // CHECK: async.await %[[S2]] : !async.token
    // CHECK: stor.unpack
    // CHECK-NOT: sched.pipeline
    // CHECK-NOT: sched.stage
    // CHECK-NOT: sched.concurrent
    // CHECK-NOT: sched.task
    // CHECK-NOT: sched.wait
    // CHECK-NOT: comm.stream
    %e = comm.stream %w_ssd, %w_hbm : !stor.buffer<tensor<4xf32>, ssd>, !stor.buffer<tensor<4xf32>, hbm> -> !sched.token
    sched.wait %e : !sched.token

    sched.pipeline {
      sched.stage "prepare" {
        stor.pack %t into %a_hbm : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
        sched.yield
      }
      sched.stage "execute" {
        sched.concurrent {
          %tc = sched.task {
            %w = stor.unpack %w_hbm : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
            %a = stor.unpack %a_hbm : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
            %y = comp.elemwise %a {kind = #comp.elemwise<silu>} : tensor<4xf32> -> tensor<4xf32>
            sched.yield
          }
          %ts = sched.task {
            %spill = comm.stream %a_hbm, %a_ssd : !stor.buffer<tensor<4xf32>, hbm>, !stor.buffer<tensor<4xf32>, ssd> -> !sched.token
            sched.yield
          }
          sched.yield
        }
        sched.yield
      }
      sched.yield
    }

    %out = stor.unpack %a_hbm : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    return %out : tensor<4xf32>
  }
}
