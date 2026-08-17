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
}
