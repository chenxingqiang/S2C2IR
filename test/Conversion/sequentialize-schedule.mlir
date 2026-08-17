// RUN: s2c2-opt %s --sequentialize-s2c2-schedule | FileCheck %s

module {
  // CHECK-LABEL: func.func @overlap_comm_then_compute
  func.func @overlap_comm_then_compute(%v: tensor<4xf32>) -> tensor<4xf32> {
    %src = stor.alloc : !stor.buffer<tensor<4xf32>, ssd>
    %dst = stor.alloc : !stor.buffer<tensor<4xf32>, hbm>
    // CHECK: comm.copy
    // CHECK-NOT: sched.overlap
    // CHECK: return %{{.*}} : tensor<4xf32>
    %y = sched.overlap -> tensor<4xf32> {
      sched.yield %v : tensor<4xf32>
    } {
      comm.copy %src, %dst : !stor.buffer<tensor<4xf32>, ssd>, !stor.buffer<tensor<4xf32>, hbm>
      sched.yield
    }
    return %y : tensor<4xf32>
  }

  // CHECK-LABEL: func.func @concurrent_ir_order
  func.func @concurrent_ir_order(%v: tensor<4xf32>) -> tensor<4xf32> {
    %w = stor.object : !stor.object<tensor<4xf32>>
    %ssd = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, ssd>
    %hbm = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    // Stream task is first so sequentialize fills HBM before the yield.
    // CHECK: comm.stream
    // CHECK-NOT: sched.concurrent
    // CHECK-NOT: sched.task
    // CHECK-NOT: sched.wait
    %y = sched.concurrent -> tensor<4xf32> {
      %ts = sched.task {
        %t = comm.stream %ssd, %hbm : !stor.buffer<tensor<4xf32>, ssd>, !stor.buffer<tensor<4xf32>, hbm> -> !sched.token
        sched.yield
      }
      %tc, %out = sched.task -> tensor<4xf32> {
        sched.wait %ts : !sched.token
        sched.yield %v : tensor<4xf32>
      }
      sched.yield %out : tensor<4xf32>
    }
    return %y : tensor<4xf32>
  }

  // Sequentialize is a blocking baseline: wait/barrier are completion
  // consumers and are erased after making producers synchronous.
  // CHECK-LABEL: func.func @erase_wait_after_stream
  func.func @erase_wait_after_stream(%v: tensor<4xf32>) -> tensor<4xf32> {
    %src = stor.alloc : !stor.buffer<tensor<4xf32>, ssd>
    %dst = stor.alloc : !stor.buffer<tensor<4xf32>, hbm>
    %t = comm.stream %src, %dst : !stor.buffer<tensor<4xf32>, ssd>, !stor.buffer<tensor<4xf32>, hbm> -> !sched.token
    sched.wait %t : !sched.token
    // CHECK: comm.stream
    // CHECK-NOT: sched.wait
    return %v : tensor<4xf32>
  }
}
