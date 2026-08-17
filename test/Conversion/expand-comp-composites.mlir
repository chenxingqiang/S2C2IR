// RUN: s2c2-opt %s --expand-comp-composites | FileCheck %s

module {
  // CHECK-LABEL: func.func @expand_silu
  func.func @expand_silu(%x: tensor<1x4xf32>, %wg: tensor<4x8xf32>,
                         %wu: tensor<4x8xf32>, %wd: tensor<8x4xf32>)
      -> tensor<1x4xf32> {
    // CHECK-NOT: comp.gated_mlp
    // CHECK: %[[GATE:.*]] = comp.matmul %{{.*}}, %{{.*}} {unit = #comp.unit<npu>}
    // CHECK: %[[UP:.*]] = comp.matmul %{{.*}}, %{{.*}} {unit = #comp.unit<npu>}
    // CHECK: %[[ACT:.*]] = comp.elemwise %[[GATE]] {kind = #comp.elemwise<silu>, unit = #comp.unit<npu>}
    // CHECK: %[[HID:.*]] = comp.elemwise %[[ACT]], %[[UP]] {kind = #comp.elemwise<mul>, unit = #comp.unit<npu>}
    // CHECK: %[[OUT:.*]] = comp.matmul %[[HID]], %{{.*}} {unit = #comp.unit<npu>}
    // CHECK: return %[[OUT]]
    %y = comp.gated_mlp %x, %wg, %wu, %wd {activation = #comp.activation<silu>, unit = #comp.unit<npu>}
      : tensor<1x4xf32>, tensor<4x8xf32>, tensor<4x8xf32>, tensor<8x4xf32> -> tensor<1x4xf32>
    return %y : tensor<1x4xf32>
  }
}
