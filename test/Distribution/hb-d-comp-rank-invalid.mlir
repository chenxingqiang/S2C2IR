// RUN: s2c2-opt %s --check-s2c2-hb-d -verify-diagnostics

module {
  shard.grid @tp(shape = 2)

  func.func @id_mixed_rank_compute(%lhs: tensor<4x8xf32>, %rhs: tensor<8x4xf32>) -> tensor<4x4xf32> {
    %replicated = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %ga = stor.object : !stor.object<tensor<4x8xf32>>
    %gb = stor.object : !stor.object<tensor<8x4xf32>>
    %a0 = stor.localize %ga to %replicated rank = 0 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<4x8xf32>>
    %a1 = stor.localize %ga to %replicated rank = 1 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<4x8xf32>>
    %b0 = stor.localize %gb to %replicated rank = 0 : !stor.object<tensor<8x4xf32>>, !shard.sharding -> !stor.object<tensor<8x4xf32>>
    %b1 = stor.localize %gb to %replicated rank = 1 : !stor.object<tensor<8x4xf32>>, !shard.sharding -> !stor.object<tensor<8x4xf32>>
    %in0 = stor.materialize %a0 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    %in1 = stor.materialize %b1 : !stor.object<tensor<8x4xf32>> -> !stor.buffer<tensor<8x4xf32>, hbm>
    stor.pack %lhs into %in0 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %rhs into %in1 : tensor<8x4xf32>, !stor.buffer<tensor<8x4xf32>, hbm>
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    %u1 = stor.unpack %in1 : !stor.buffer<tensor<8x4xf32>, hbm> -> tensor<8x4xf32>
    // expected-error @+1 {{compute operands are on different ranks}}
    %y = comp.matmul %u0, %u1 : tensor<4x8xf32>, tensor<8x4xf32> -> tensor<4x4xf32>
    return %y : tensor<4x4xf32>
  }
}
