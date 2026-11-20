// RUN: s2c2-opt %s --check-s2c2-hb-d -split-input-file -verify-diagnostics

module {
  shard.grid @g(shape = 2)

  func.func @f01(%partial: tensor<4xf32>) {
    %w = stor.object : !stor.object<tensor<4xf32>>
    %a = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %b = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %a : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    %u = stor.unpack %a : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    // expected-error @+1 {{HBM residencies are not mesh participants}}
    %c = shard.all_reduce %u on @g grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    return
  }
}

// -----

module {
  shard.grid @g(shape = 2x2)

  func.func @f02(%partial: tensor<4xf32>) {
    // expected-error @+1 {{rank is outside the mesh}}
    %c = shard.all_reduce %partial on @g grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    return
  }
}

// -----

module {
  shard.grid @tp(shape = 2)

  // expected-error @+1 {{shards do not cover the global tensor}}
  func.func @f03() {
    %sharding = shard.sharding @tp split_axes = [[0]] sharded_dims_offsets = [0, 2, 3] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4x8xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<2x8xf32>>
    %l1 = stor.localize %global to %sharding rank = 1 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<1x8xf32>>
    return
  }
}

// -----

module {
  shard.grid @tp(shape = 2)

  func.func @f04() {
    %sharding = shard.sharding @tp split_axes = [[0]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4x8xf32>>
    // expected-error @+1 {{local shape is not the shard tile}}
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<4x8xf32>>
    return
  }
}

// -----

module {
  shard.grid @g(shape = 2)

  func.func @f05(%partial: tensor<4xf32>) {
    %w = stor.object : !stor.object<tensor<4xf32>>
    %a = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %b = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %a : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    // expected-error @+1 {{pairwise copy is not a collective}}
    comm.copy %a, %b : !stor.buffer<tensor<4xf32>, hbm>, !stor.buffer<tensor<4xf32>, hbm>
    return
  }
}

// -----

module {
  shard.grid @tp(shape = 2)

  func.func @f06(%partial: tensor<4xf32>) {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %l1 = stor.localize %global to %sharding rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %in0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %in1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %out0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %out1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %u1 = stor.unpack %in1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %c0 = shard.all_reduce %u0 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %c1 = shard.all_reduce %u1 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    // The output residency is readable. This read is not the collective result.
    // expected-error @+1 {{collective result is not valid}}
    %stale = stor.unpack %out0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    stor.pack %c0 into %out0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %c1 into %out1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    return
  }
}

// -----

module {
  shard.grid @tp(shape = 2)

  // expected-error @+1 {{missing mesh rank}}
  func.func @f07(%partial: tensor<4xf32>) {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %in0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %c = shard.all_reduce %u0 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %out0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %c into %out0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    return
  }
}

// -----

module {
  shard.grid @tp(shape = 2)

  func.func @f08(%partial: tensor<4xf32>) {
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
        // expected-error @+1 {{rank pack does not enter the collective}}
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

// -----

module {
  shard.grid @tp(shape = 2)

  func.func @f07_result_not_packed(%partial: tensor<4xf32>) {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %l1 = stor.localize %global to %sharding rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %in0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %in1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %u1 = stor.unpack %in1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %c0 = shard.all_reduce %u0 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    // expected-error @+1 {{collective drops a participant}}
    %c1 = shard.all_reduce %u1 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    stor.pack %c0 into %out0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    return
  }
}
