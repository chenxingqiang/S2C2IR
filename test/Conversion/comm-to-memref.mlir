// RUN: s2c2-opt %s --convert-comm-to-memref | FileCheck %s

module {
  // CHECK-LABEL: func.func @stream_and_copy
  func.func @stream_and_copy() {
    %src = stor.alloc : !stor.buffer<tensor<2x4xf32>, ssd>
    %dst = stor.alloc : !stor.buffer<tensor<2x4xf32>, hbm>
    // CHECK: %[[SSD:.*]] = memref.alloc() : memref<2x4xf32, 4>
    // CHECK: %[[HBM:.*]] = memref.alloc() : memref<2x4xf32, 3>
    // CHECK: memref.copy %[[SSD]], %[[HBM]]
    %t = comm.stream %src, %dst : !stor.buffer<tensor<2x4xf32>, ssd>, !stor.buffer<tensor<2x4xf32>, hbm> -> !sched.token
    // CHECK: memref.copy %[[SSD]], %[[HBM]]
    comm.copy %src, %dst : !stor.buffer<tensor<2x4xf32>, ssd>, !stor.buffer<tensor<2x4xf32>, hbm>
    // CHECK-NOT: sched.wait
    sched.wait %t : !sched.token
    // CHECK: memref.dealloc %[[SSD]]
    stor.dealloc %src : !stor.buffer<tensor<2x4xf32>, ssd>
    stor.dealloc %dst : !stor.buffer<tensor<2x4xf32>, hbm>
    return
  }
}
