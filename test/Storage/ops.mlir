// RUN: s2c2-opt %s | s2c2-opt | FileCheck %s

module {
  // CHECK-LABEL: func.func @buffers
  func.func @buffers(%t: tensor<2x4xf32>) {
    // CHECK: %[[SSD:.*]] = stor.alloc : !stor.buffer<tensor<2x4xf32>, ssd>
    %ssd = stor.alloc : !stor.buffer<tensor<2x4xf32>, ssd>
    // CHECK: %[[HBM:.*]] = stor.alloc : !stor.buffer<tensor<2x4xf32>, hbm>
    %hbm = stor.alloc : !stor.buffer<tensor<2x4xf32>, hbm>
    // CHECK: stor.pack %{{.*}} into %[[HBM]] : tensor<2x4xf32>, !stor.buffer<tensor<2x4xf32>, hbm>
    stor.pack %t into %hbm : tensor<2x4xf32>, !stor.buffer<tensor<2x4xf32>, hbm>
    // CHECK: %[[OUT:.*]] = stor.unpack %[[HBM]] : !stor.buffer<tensor<2x4xf32>, hbm> -> tensor<2x4xf32>
    %out = stor.unpack %hbm : !stor.buffer<tensor<2x4xf32>, hbm> -> tensor<2x4xf32>
    // CHECK: stor.dealloc %[[SSD]] : !stor.buffer<tensor<2x4xf32>, ssd>
    stor.dealloc %ssd : !stor.buffer<tensor<2x4xf32>, ssd>
    // CHECK: stor.dealloc %[[HBM]] : !stor.buffer<tensor<2x4xf32>, hbm>
    stor.dealloc %hbm : !stor.buffer<tensor<2x4xf32>, hbm>
    return
  }
}
