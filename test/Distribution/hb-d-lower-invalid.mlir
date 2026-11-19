// RUN: s2c2-opt %s --check-s2c2-hb-d-fidelity=mode=async -split-input-file -verify-diagnostics
// RUN: s2c2-opt %s --check-s2c2-hb-d-fidelity=mode=sync -split-input-file -verify-diagnostics

module {
  shard.grid @tp(shape = 2)

  func.func @f07_dropped_rank(%partial: tensor<4xf32>) {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %in0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    // expected-error @+1 {{collective drops a participant}}
    %c = shard.all_reduce %u0 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %out0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %c into %out0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    return
  }
}

// -----

module {
  shard.grid @tp(shape = 2)

  func.func @f08_deleted_edge(%partial: tensor<4xf32>) {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %l1 = stor.localize %global to %sharding rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    sched.concurrent {
      %t0 = sched.task {
        stor.pack %partial into %in0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
        %u0 = stor.unpack %in0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
        // expected-error @+1 {{missing cross-rank happens-before}}
        %c = shard.all_reduce %u0 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
        stor.pack %c into %out0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
        stor.pack %c into %out1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
        sched.yield
      }
      %t1 = sched.task {
        stor.pack %partial into %in1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
        sched.yield
      }
      sched.yield
    }
    return
  }
}
