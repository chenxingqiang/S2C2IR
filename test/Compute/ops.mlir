// RUN: s2c2-opt %s | s2c2-opt | FileCheck %s

module {
  // CHECK-LABEL: func.func @kernels
  func.func @kernels(%x: tensor<1x4xf32>, %w: tensor<4x4xf32>,
                     %wg: tensor<4x8xf32>, %wu: tensor<4x8xf32>,
                     %wd: tensor<8x4xf32>) {
    // CHECK: %[[MM:.*]] = comp.matmul %{{.*}}, %{{.*}} {unit = #comp.unit<gpu>} : tensor<1x4xf32>, tensor<4x4xf32> -> tensor<1x4xf32>
    %mm = comp.matmul %x, %w {unit = #comp.unit<gpu>} : tensor<1x4xf32>, tensor<4x4xf32> -> tensor<1x4xf32>
    // CHECK: %[[EW:.*]] = comp.elemwise %[[MM]] {kind = #comp.elemwise<silu>} : tensor<1x4xf32> -> tensor<1x4xf32>
    %ew = comp.elemwise %mm {kind = #comp.elemwise<silu>} : tensor<1x4xf32> -> tensor<1x4xf32>
    // CHECK: %{{.*}} = comp.gated_mlp %{{.*}}, %{{.*}}, %{{.*}}, %{{.*}} {activation = #comp.activation<silu>, unit = #comp.unit<npu>}
    %y = comp.gated_mlp %x, %wg, %wu, %wd {activation = #comp.activation<silu>, unit = #comp.unit<npu>}
      : tensor<1x4xf32>, tensor<4x8xf32>, tensor<4x8xf32>, tensor<8x4xf32> -> tensor<1x4xf32>
    return
  }
}
