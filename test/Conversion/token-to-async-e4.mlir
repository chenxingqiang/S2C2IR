// RUN: s2c2-opt %s --convert-s2c2-token-to-async | FileCheck %s

// E4: wait(event(T1)) becomes await of T1's execute token (HB preserved).
module {
  // CHECK-LABEL: func.func @e4_wait_producer_task
  func.func @e4_wait_producer_task(%t: tensor<4xf32>) -> tensor<4xf32> {
    %w = stor.object : !stor.object<tensor<4xf32>>
    %ssd = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, ssd>
    %hbm = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %t into %ssd : tensor<4xf32>, !stor.buffer<tensor<4xf32>, ssd>
    // CHECK: %[[T1:.*]] = async.execute
    // CHECK: comm.copy
    // CHECK: sched.task
    // CHECK: async.await %[[T1]] : !async.token
    // CHECK: stor.unpack
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
