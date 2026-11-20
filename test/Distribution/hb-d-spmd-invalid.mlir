// RUN: s2c2-opt %s --check-s2c2-hb-d -split-input-file -verify-diagnostics

module {
  shard.grid @tp(shape = 2)

  func.func @d09_unrelated_operand(%partial: tensor<4xf32>) {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %l1 = stor.localize %global to %sharding rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %in0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %in1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    // expected-error @+1 {{collective operand is not this rank's local tensor}}
    %c = shard.all_reduce %partial on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    return
  }
}

// -----

module {
  shard.grid @tp(shape = 2)

  func.func @d10_pack_does_not_enter(%partial: tensor<4xf32>) {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %l1 = stor.localize %global to %sharding rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %in0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %in1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    // expected-error @+1 {{rank pack does not enter the collective}}
    %c = shard.all_reduce %u0 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %out0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %c into %out0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    return
  }
}

// -----

module {
  shard.grid @tp(shape = 2)

  func.func @d12_all_gather_result_layout(%tile: tensor<2x1xf32>) {
    %inShard = shard.sharding @tp split_axes = [[], [0]] : !shard.sharding
    %outShard = shard.sharding @tp split_axes = [[], [0]] : !shard.sharding
    %inGlobal = stor.object : !stor.object<tensor<2x2xf32>>
    %outGlobal = stor.object : !stor.object<tensor<4x2xf32>>
    %l0 = stor.localize %inGlobal to %inShard rank = 0 : !stor.object<tensor<2x2xf32>>, !shard.sharding -> !stor.object<tensor<2x1xf32>>
    %l1 = stor.localize %inGlobal to %inShard rank = 1 : !stor.object<tensor<2x2xf32>>, !shard.sharding -> !stor.object<tensor<2x1xf32>>
    %g0 = stor.localize %outGlobal to %outShard rank = 0 : !stor.object<tensor<4x2xf32>>, !shard.sharding -> !stor.object<tensor<4x1xf32>>
    %g1 = stor.localize %outGlobal to %outShard rank = 1 : !stor.object<tensor<4x2xf32>>, !shard.sharding -> !stor.object<tensor<4x1xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<2x1xf32>> -> !stor.buffer<tensor<2x1xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<2x1xf32>> -> !stor.buffer<tensor<2x1xf32>, hbm>
    stor.pack %tile into %in0 : tensor<2x1xf32>, !stor.buffer<tensor<2x1xf32>, hbm>
    stor.pack %tile into %in1 : tensor<2x1xf32>, !stor.buffer<tensor<2x1xf32>, hbm>
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<2x1xf32>, hbm> -> tensor<2x1xf32>
    %u1 = stor.unpack %in1 : !stor.buffer<tensor<2x1xf32>, hbm> -> tensor<2x1xf32>
    // Gather shape is legal. The result residency is still sharded.
    // expected-error @+1 {{all-gather result is not replicated}}
    %c0 = shard.all_gather %u0 on @tp grid_axes = [0] gather_axis = 0 : tensor<2x1xf32> -> tensor<4x1xf32>
    %c1 = shard.all_gather %u1 on @tp grid_axes = [0] gather_axis = 0 : tensor<2x1xf32> -> tensor<4x1xf32>
    %out0 = stor.materialize %g0 : !stor.object<tensor<4x1xf32>> -> !stor.buffer<tensor<4x1xf32>, hbm>
    %out1 = stor.materialize %g1 : !stor.object<tensor<4x1xf32>> -> !stor.buffer<tensor<4x1xf32>, hbm>
    stor.pack %c0 into %out0 : tensor<4x1xf32>, !stor.buffer<tensor<4x1xf32>, hbm>
    stor.pack %c1 into %out1 : tensor<4x1xf32>, !stor.buffer<tensor<4x1xf32>, hbm>
    return
  }
}

// -----

module {
  shard.grid @tp(shape = 2)

  func.func @d13_reduce_scatter_input_layout(%tile: tensor<2xf32>) {
    %sharded = shard.sharding @tp split_axes = [[0]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4xf32>>
    %l0 = stor.localize %global to %sharded rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<2xf32>>
    %l1 = stor.localize %global to %sharded rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<2xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<2xf32>> -> !stor.buffer<tensor<2xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<2xf32>> -> !stor.buffer<tensor<2xf32>, hbm>
    stor.pack %tile into %in0 : tensor<2xf32>, !stor.buffer<tensor<2xf32>, hbm>
    stor.pack %tile into %in1 : tensor<2xf32>, !stor.buffer<tensor<2xf32>, hbm>
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<2xf32>, hbm> -> tensor<2xf32>
    %u1 = stor.unpack %in1 : !stor.buffer<tensor<2xf32>, hbm> -> tensor<2xf32>
    // expected-error @+1 {{reduce-scatter input is not replicated}}
    %c0 = shard.reduce_scatter %u0 on @tp grid_axes = [0] scatter_axis = 0 : tensor<2xf32> -> tensor<1xf32>
    %c1 = shard.reduce_scatter %u1 on @tp grid_axes = [0] scatter_axis = 0 : tensor<2xf32> -> tensor<1xf32>
    return
  }
}

// -----

module {
  shard.grid @left(shape = 2)
  shard.grid @right(shape = 2)

  func.func @d11_wrong_mesh() {
    %left = shard.sharding @left split_axes = [[]] : !shard.sharding
    %right = shard.sharding @right split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4xf32>>
    %ok = stor.localize %global to %left rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    // expected-error @+1 {{localize mesh does not match}}
    %bad = stor.localize %global to %right rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    return
  }
}

// -----

module {
  shard.grid @tp(shape = 2)

  func.func @d16_duplicate_rank() {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %l1 = stor.localize %global to %sharding rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    // expected-error @+1 {{duplicate mesh rank}}
    %again = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    return
  }
}

// -----

module {
  shard.grid @tp(shape = 2)

  // expected-error @+1 {{missing mesh rank}}
  func.func @d16_missing_rank() {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    return
  }
}
