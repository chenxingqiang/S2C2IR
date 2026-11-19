// RUN: s2c2-opt %s --check-s2c2-hb-d -split-input-file
// RUN: s2c2-opt %s --check-s2c2-execution -split-input-file

// D01: tensor-parallel all-reduce. Each rank holds the full partial.
// The matmul unpacks the result residency, so it is after the collective.

module {
  shard.grid @tp(shape = 2)

  func.func @d01_tensor_parallel_all_reduce(%partial: tensor<4x8xf32>, %rhs: tensor<8x4xf32>) -> tensor<4x4xf32> {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4x8xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<4x8xf32>>
    %l1 = stor.localize %global to %sharding rank = 1 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<4x8xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %partial into %in0 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %partial into %in1 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    %u1 = stor.unpack %in1 : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    %c = shard.all_reduce %u0 on @tp grid_axes = [0] : tensor<4x8xf32> -> tensor<4x8xf32>
    %out0 = stor.materialize %l0 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    %out1 = stor.materialize %l1 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %c into %out0 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %c into %out1 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    %reduced = stor.unpack %out0 : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    %y = comp.matmul %reduced, %rhs : tensor<4x8xf32>, tensor<8x4xf32> -> tensor<4x4xf32>
    return %y : tensor<4x4xf32>
  }

  func.func @d02_all_gather(%tile: tensor<2x8xf32>) {
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
    %c = shard.all_gather %u0 on @tp grid_axes = [0] gather_axis = 0 : tensor<2x8xf32> -> tensor<4x8xf32>
    %out0 = stor.materialize %g0 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    %out1 = stor.materialize %g1 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %c into %out0 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %c into %out1 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    %y = stor.unpack %out0 : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    return
  }

  func.func @d02_reduce_scatter(%partial: tensor<4x8xf32>) {
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
    %c = shard.reduce_scatter %u0 on @tp grid_axes = [0] scatter_axis = 0 : tensor<4x8xf32> -> tensor<2x8xf32>
    %out0 = stor.materialize %s0 : !stor.object<tensor<2x8xf32>> -> !stor.buffer<tensor<2x8xf32>, hbm>
    %out1 = stor.materialize %s1 : !stor.object<tensor<2x8xf32>> -> !stor.buffer<tensor<2x8xf32>, hbm>
    stor.pack %c into %out0 : tensor<2x8xf32>, !stor.buffer<tensor<2x8xf32>, hbm>
    stor.pack %c into %out1 : tensor<2x8xf32>, !stor.buffer<tensor<2x8xf32>, hbm>
    %y = stor.unpack %out0 : !stor.buffer<tensor<2x8xf32>, hbm> -> tensor<2x8xf32>
    return
  }

  // One rank holds the partial in host and in hbm. The stream is an
  // intra-rank move. The mesh participants are the two ranks.
  func.func @d05_multilevel_storage(%partial: tensor<4x8xf32>) {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4x8xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<4x8xf32>>
    %l1 = stor.localize %global to %sharding rank = 1 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<4x8xf32>>
    %host = stor.materialize %l0 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, host>
    %hbm0 = stor.materialize %l0 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    %hbm1 = stor.materialize %l1 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %partial into %host : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, host>
    %tok = comm.stream %host, %hbm0 : !stor.buffer<tensor<4x8xf32>, host>, !stor.buffer<tensor<4x8xf32>, hbm> -> !sched.token
    sched.wait %tok : !sched.token
    stor.pack %partial into %hbm1 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    %u0 = stor.unpack %hbm0 : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    %u1 = stor.unpack %hbm1 : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    %c = shard.all_reduce %u0 on @tp grid_axes = [0] : tensor<4x8xf32> -> tensor<4x8xf32>
    %out0 = stor.materialize %l0 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    %out1 = stor.materialize %l1 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %c into %out0 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %c into %out1 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    %y = stor.unpack %out0 : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    return
  }
}

// -----

module {
  shard.grid @solo(shape = 1)

  func.func @mesh_size_one(%partial: tensor<4x8xf32>) -> tensor<4x8xf32> {
    %sharding = shard.sharding @solo split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4x8xf32>>
    %local = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<4x8xf32>>
    %in = stor.materialize %local : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %partial into %in : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    %u = stor.unpack %in : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    %c = shard.all_reduce %u on @solo grid_axes = [0] : tensor<4x8xf32> -> tensor<4x8xf32>
    %out = stor.materialize %local : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %c into %out : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    %y = stor.unpack %out : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    return %y : tensor<4x8xf32>
  }
}
