// Waiting for rank 0 does not complete rank 1's task pack. The last op in
// the task body is not that completion; the pack stays invalid until rank 1's
// own token is waited.
// RUN: s2c2-opt %s --check-s2c2-hb-d -split-input-file -verify-diagnostics

module {
  shard.grid @tp(shape = 2)

  func.func @id_wait_rank0_leaves_rank1(%partial: tensor<4xf32>) {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %l1 = stor.localize %global to %sharding rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %t0 = sched.task {
      stor.pack %partial into %in0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
      sched.yield
    }
    %t1 = sched.task {
      stor.pack %partial into %in1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
      sched.yield
    }
    sched.wait %t0 : !sched.token
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %u1 = stor.unpack %in1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %c0 = shard.all_reduce %u0 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    // expected-error @+1 {{collective input is not valid on every path}}
    %c1 = shard.all_reduce %u1 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    stor.pack %c0 into %out0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %c1 into %out1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    return
  }
}

// -----

module {
  shard.grid @tp(shape = 2)

  func.func @id_pack_used_before_wait(%partial: tensor<4xf32>) {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %l1 = stor.localize %global to %sharding rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %t0 = sched.task {
      stor.pack %partial into %in0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
      sched.yield
    }
    %t1 = sched.task {
      stor.pack %partial into %in1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
      sched.yield
    }
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %u1 = stor.unpack %in1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    // expected-error @+1 {{collective input is not valid on every path}}
    %c0 = shard.all_reduce %u0 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %c1 = shard.all_reduce %u1 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    sched.wait %t0, %t1 : !sched.token, !sched.token
    stor.pack %c0 into %out0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %c1 into %out1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    return
  }
}
