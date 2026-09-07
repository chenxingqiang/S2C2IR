// RUN: s2c2-opt %s --convert-s2c2-token-to-async --convert-s2c2-concurrent-to-async | FileCheck %s

// C3: cross-sibling wait(event(T1)) is await of T1 inside T2, not a
// parent-level await that would serialize launch.
module {
  // CHECK-LABEL: func.func @c3_cross_sibling_wait
  func.func @c3_cross_sibling_wait(%t: tensor<4xf32>) -> tensor<4xf32> {
    %w = stor.object : !stor.object<tensor<4xf32>>
    %ssd = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, ssd>
    %hbm = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %t into %ssd : tensor<4xf32>, !stor.buffer<tensor<4xf32>, ssd>
    // CHECK: %[[T1:.*]] = async.execute {
    // CHECK:   comm.copy
    // CHECK:   async.yield
    // CHECK: }
    // CHECK: %[[T2:.*]], %[[VAL:.*]] = async.execute
    // CHECK-SAME: -> !async.value<tensor<4xf32>> {
    // CHECK:   async.await %[[T1]] : !async.token
    // CHECK:   stor.unpack
    // CHECK:   async.yield
    // CHECK: }
    // CHECK: %[[OUT:.*]] = async.await %[[VAL]] : !async.value<tensor<4xf32>>
    // CHECK: return %[[OUT]]
    // CHECK-NOT: async.await %[[T1]]
    // CHECK-NOT: sched.concurrent
    // CHECK-NOT: sched.task
    // CHECK-NOT: sched.wait
    %y = sched.concurrent -> tensor<4xf32> {
      %t1 = sched.task {
        %e = comm.stream %ssd, %hbm : !stor.buffer<tensor<4xf32>, ssd>, !stor.buffer<tensor<4xf32>, hbm> -> !sched.token
        sched.yield
      }
      %t2, %out = sched.task -> tensor<4xf32> {
        sched.wait %t1 : !sched.token
        %v = stor.unpack %hbm : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
        sched.yield %v : tensor<4xf32>
      }
      sched.yield %out : tensor<4xf32>
    }
    return %y : tensor<4xf32>
  }
}
