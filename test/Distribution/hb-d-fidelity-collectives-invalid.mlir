// A rank whose collective result is never packed is still dropped after
// async and sync lowering.
// RUN: s2c2-opt %s --lower-s2c2-hb-d=async --check-s2c2-hb-d-fidelity=mode=async -split-input-file -verify-diagnostics
// RUN: s2c2-opt %s --lower-s2c2-hb-d=sync --check-s2c2-hb-d-fidelity=mode=sync -split-input-file -verify-diagnostics

module {
  shard.grid @tp(shape = 2)

  func.func @id_all_gather_no_result(%tile: tensor<2x8xf32>) {
    %sharded = shard.sharding @tp split_axes = [[0]] : !shard.sharding
    %replicated = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4x8xf32>>
    %gathered = stor.object : !stor.object<tensor<4x8xf32>>
    %l0 = stor.localize %global to %sharded rank = 0 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<2x8xf32>>
    %l1 = stor.localize %global to %sharded rank = 1 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<2x8xf32>>
    %g0 = stor.localize %gathered to %replicated rank = 0 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<4x8xf32>>
    %g1 = stor.localize %gathered to %replicated rank = 1 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<4x8xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<2x8xf32>> -> !stor.buffer<tensor<2x8xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<2x8xf32>> -> !stor.buffer<tensor<2x8xf32>, hbm>
    stor.pack %tile into %in0 : tensor<2x8xf32>, !stor.buffer<tensor<2x8xf32>, hbm>
    stor.pack %tile into %in1 : tensor<2x8xf32>, !stor.buffer<tensor<2x8xf32>, hbm>
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<2x8xf32>, hbm> -> tensor<2x8xf32>
    %u1 = stor.unpack %in1 : !stor.buffer<tensor<2x8xf32>, hbm> -> tensor<2x8xf32>
    %c0 = shard.all_gather %u0 on @tp grid_axes = [0] gather_axis = 0 : tensor<2x8xf32> -> tensor<4x8xf32>
    // expected-error @+1 {{collective drops a participant}}
    %c1 = shard.all_gather %u1 on @tp grid_axes = [0] gather_axis = 0 : tensor<2x8xf32> -> tensor<4x8xf32>
    %out0 = stor.materialize %g0 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %c0 into %out0 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    return
  }
}

// -----

module {
  shard.grid @tp(shape = 2)

  func.func @id_reduce_scatter_no_result(%partial: tensor<4x8xf32>) {
    %replicated = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %sharded = shard.sharding @tp split_axes = [[0]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4x8xf32>>
    %scattered = stor.object : !stor.object<tensor<4x8xf32>>
    %l0 = stor.localize %global to %replicated rank = 0 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<4x8xf32>>
    %l1 = stor.localize %global to %replicated rank = 1 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<4x8xf32>>
    %s0 = stor.localize %scattered to %sharded rank = 0 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<2x8xf32>>
    %s1 = stor.localize %scattered to %sharded rank = 1 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<2x8xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %partial into %in0 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %partial into %in1 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    %u1 = stor.unpack %in1 : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    %c0 = shard.reduce_scatter %u0 on @tp grid_axes = [0] scatter_axis = 0 : tensor<4x8xf32> -> tensor<2x8xf32>
    // expected-error @+1 {{collective drops a participant}}
    %c1 = shard.reduce_scatter %u1 on @tp grid_axes = [0] scatter_axis = 0 : tensor<4x8xf32> -> tensor<2x8xf32>
    %out0 = stor.materialize %s0 : !stor.object<tensor<2x8xf32>> -> !stor.buffer<tensor<2x8xf32>, hbm>
    stor.pack %c0 into %out0 : tensor<2x8xf32>, !stor.buffer<tensor<2x8xf32>, hbm>
    return
  }
}
