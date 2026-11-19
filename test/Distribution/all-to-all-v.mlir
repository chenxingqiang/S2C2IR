// RUN: s2c2-opt %s --check-s2c2-hb-d -verify-diagnostics

module {
  shard.grid @g(shape = 2)

  func.func @d03_all_to_all_v(%tile: tensor<2x4xf32>) {
    // expected-error @+1 {{all-to-all is v0.1}}
    %c = shard.all_to_all %tile on @g grid_axes = [0] split_axis = 0 concat_axis = 0 : tensor<2x4xf32> -> tensor<2x4xf32>
    return
  }
}
