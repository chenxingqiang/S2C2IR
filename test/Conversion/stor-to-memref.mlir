// RUN: s2c2-opt %s --convert-stor-to-memref | FileCheck %s

module {
  // CHECK-LABEL: func.func @alloc_hbm
  func.func @alloc_hbm() {
    // CHECK: %[[M:.*]] = memref.alloc() : memref<2x4xf32, 3>
    %0 = stor.alloc : !stor.buffer<tensor<2x4xf32>, hbm>
    // CHECK: memref.dealloc %[[M]] : memref<2x4xf32, 3>
    stor.dealloc %0 : !stor.buffer<tensor<2x4xf32>, hbm>
    return
  }

  // CHECK-LABEL: func.func @alloc_ssd
  func.func @alloc_ssd() {
    // CHECK: memref.alloc() : memref<8xf16, 4>
    %0 = stor.alloc : !stor.buffer<tensor<8xf16>, ssd>
    stor.dealloc %0 : !stor.buffer<tensor<8xf16>, ssd>
    return
  }
}
