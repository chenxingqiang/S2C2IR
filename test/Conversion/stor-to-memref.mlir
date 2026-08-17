// RUN: s2c2-opt %s --convert-stor-to-memref | FileCheck %s
// RUN: s2c2-opt %s --convert-stor-to-memref="space-map=hbm=9,ssd=100" | FileCheck %s --check-prefix=MAP

module {
  // CHECK-LABEL: func.func @alloc_hbm
  // MAP-LABEL: func.func @alloc_hbm
  func.func @alloc_hbm() {
    // CHECK: %[[M:.*]] = memref.alloc() : memref<2x4xf32, 3>
    // MAP: memref.alloc() : memref<2x4xf32, 9>
    %0 = stor.alloc : !stor.buffer<tensor<2x4xf32>, hbm>
    // CHECK: memref.dealloc %[[M]] : memref<2x4xf32, 3>
    stor.dealloc %0 : !stor.buffer<tensor<2x4xf32>, hbm>
    return
  }

  // CHECK-LABEL: func.func @alloc_ssd
  // MAP-LABEL: func.func @alloc_ssd
  func.func @alloc_ssd() {
    // CHECK: memref.alloc() : memref<8xf16, 4>
    // MAP: memref.alloc() : memref<8xf16, 100>
    %0 = stor.alloc : !stor.buffer<tensor<8xf16>, ssd>
    stor.dealloc %0 : !stor.buffer<tensor<8xf16>, ssd>
    return
  }

  // CHECK-LABEL: func.func @object_materialize_transfer
  func.func @object_materialize_transfer() {
    %w = stor.object : !stor.object<tensor<2x4xf32>>
    // CHECK: %[[SSD:.*]] = memref.alloc() : memref<2x4xf32, 4>
    %ssd = stor.materialize %w : !stor.object<tensor<2x4xf32>> -> !stor.buffer<tensor<2x4xf32>, ssd>
    // CHECK: %[[HBM:.*]] = memref.alloc() : memref<2x4xf32, 3>
    // CHECK: memref.copy %[[SSD]], %[[HBM]]
    %hbm = stor.transfer %ssd : !stor.buffer<tensor<2x4xf32>, ssd> -> !stor.buffer<tensor<2x4xf32>, hbm>
    // CHECK-NOT: stor.object
    // CHECK: memref.dealloc %[[SSD]]
    stor.dealloc %ssd : !stor.buffer<tensor<2x4xf32>, ssd>
    stor.dealloc %hbm : !stor.buffer<tensor<2x4xf32>, hbm>
    return
  }
}
