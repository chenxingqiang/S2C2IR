// A pack inside sched.task is not an input until sched.wait. The waited
// case is @id_wait_token_frontier.
// RUN: s2c2-opt %s --check-s2c2-hb-d -split-input-file -verify-diagnostics

module {
  shard.grid @tp(shape = 2)

  func.func @id_task_pack_without_wait(%partial: tensor<4xf32>) {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %l1 = stor.localize %global to %sharding rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %in1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    %tok = sched.task {
      stor.pack %partial into %in0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
      sched.yield
    }
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %u1 = stor.unpack %in1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    // expected-error @+1 {{collective input is not valid on every path}}
    %c0 = shard.all_reduce %u0 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %c1 = shard.all_reduce %u1 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    stor.pack %c0 into %out0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %c1 into %out1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    return
  }
}
