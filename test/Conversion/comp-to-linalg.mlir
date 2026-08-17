// RUN: s2c2-opt %s --convert-comp-to-linalg | FileCheck %s

module {
  // CHECK-LABEL: func.func @matmul
  func.func @matmul(%x: tensor<1x4xf32>, %w: tensor<4x4xf32>) -> tensor<1x4xf32> {
    // CHECK: arith.constant 0.000000e+00 : f32
    // CHECK: %[[EMPTY:.*]] = tensor.empty() : tensor<1x4xf32>
    // CHECK: %[[INIT:.*]] = linalg.fill ins(%{{.*}} : f32) outs(%[[EMPTY]] : tensor<1x4xf32>)
    // CHECK: %[[OUT:.*]] = linalg.matmul ins(%{{.*}}, %{{.*}} : tensor<1x4xf32>, tensor<4x4xf32>) outs(%[[INIT]] : tensor<1x4xf32>)
    // CHECK: return %[[OUT]]
    %y = comp.matmul %x, %w : tensor<1x4xf32>, tensor<4x4xf32> -> tensor<1x4xf32>
    return %y : tensor<1x4xf32>
  }

  // CHECK-LABEL: func.func @elemwise
  func.func @elemwise(%a: tensor<4xf32>, %b: tensor<4xf32>) -> tensor<4xf32> {
    // CHECK: linalg.add
    %s = comp.elemwise %a, %b {kind = #comp.elemwise<add>} : tensor<4xf32>, tensor<4xf32> -> tensor<4xf32>
    // CHECK: linalg.map
    // CHECK: math.exp
    %u = comp.elemwise %s {kind = #comp.elemwise<silu>} : tensor<4xf32> -> tensor<4xf32>
    return %u : tensor<4xf32>
  }

  // CHECK-LABEL: func.func @gated
  func.func @gated(%x: tensor<1x4xf32>, %wg: tensor<4x8xf32>,
                   %wu: tensor<4x8xf32>, %wd: tensor<8x4xf32>) -> tensor<1x4xf32> {
    // CHECK-NOT: comp.gated_mlp
    // CHECK: linalg.matmul
    // CHECK: linalg.map
    // CHECK: linalg.mul
    // CHECK: linalg.matmul
    %y = comp.gated_mlp %x, %wg, %wu, %wd {activation = #comp.activation<silu>}
      : tensor<1x4xf32>, tensor<4x8xf32>, tensor<4x8xf32>, tensor<8x4xf32> -> tensor<1x4xf32>
    return %y : tensor<1x4xf32>
  }
}
