// RUN: s2c2-opt %s | s2c2-opt | FileCheck %s

module {
  // CHECK-LABEL: func.func @moves
  func.func @moves() {
    %src = stor.alloc : !stor.buffer<tensor<2x4xf32>, ssd>
    %dst = stor.alloc : !stor.buffer<tensor<2x4xf32>, hbm>
    // CHECK: comm.copy %{{.*}}, %{{.*}} {kind = #comm.kind<p2p>} : !stor.buffer<tensor<2x4xf32>, ssd>, !stor.buffer<tensor<2x4xf32>, hbm>
    comm.copy %src, %dst {kind = #comm.kind<p2p>} : !stor.buffer<tensor<2x4xf32>, ssd>, !stor.buffer<tensor<2x4xf32>, hbm>
    // CHECK: %[[T:.*]] = comm.stream %{{.*}}, %{{.*}} {engine = #comm.engine<dma>} : !stor.buffer<tensor<2x4xf32>, ssd>, !stor.buffer<tensor<2x4xf32>, hbm> -> !sched.token
    %t = comm.stream %src, %dst {engine = #comm.engine<dma>} : !stor.buffer<tensor<2x4xf32>, ssd>, !stor.buffer<tensor<2x4xf32>, hbm> -> !sched.token
    // CHECK: comm.barrier %[[T]] : !sched.token
    comm.barrier %t : !sched.token
    return
  }

  // CHECK-LABEL: func.func @object_stream_and_async_copy
  func.func @object_stream_and_async_copy() {
    %w = stor.object : !stor.object<tensor<2x4xf32>>
    %ssd = stor.materialize %w : !stor.object<tensor<2x4xf32>> -> !stor.buffer<tensor<2x4xf32>, ssd>
    %hbm = stor.materialize %w : !stor.object<tensor<2x4xf32>> -> !stor.buffer<tensor<2x4xf32>, hbm>
    %hbm2 = stor.materialize %w : !stor.object<tensor<2x4xf32>> -> !stor.buffer<tensor<2x4xf32>, hbm>
    // CHECK: comm.stream %{{.*}}, %{{.*}} -> !sched.token
    %t0 = comm.stream %ssd, %hbm {engine = #comm.engine<dma>}
      : !stor.buffer<tensor<2x4xf32>, ssd>, !stor.buffer<tensor<2x4xf32>, hbm> -> !sched.token
    // CHECK: comm.copy %{{.*}}, %{{.*}} -> !sched.token
    %t1 = comm.copy %hbm, %hbm2
      : !stor.buffer<tensor<2x4xf32>, hbm>, !stor.buffer<tensor<2x4xf32>, hbm> -> !sched.token
    comm.barrier %t0, %t1 : !sched.token, !sched.token
    return
  }
}
