// RUN: s2c2-opt %s --check-s2c2-hb-d -split-input-file
// RUN: s2c2-opt %s --check-s2c2-execution -split-input-file
// RUN: s2c2-opt %s --check-s2c2-distribution -split-input-file > %t.out 2> %t.err
// RUN: FileCheck %s < %t.err

// CHECK: distribution @d14_two_globals coverage=replicated:covered

module {
  shard.grid @tp(shape = 2)

  func.func @d14_two_globals() {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %left = stor.object : !stor.object<tensor<4xf32>>
    %right = stor.object : !stor.object<tensor<4xf32>>
    %l0 = stor.localize %left to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %l1 = stor.localize %left to %sharding rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %r0 = stor.localize %right to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %r1 = stor.localize %right to %sharding rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    return
  }
}

// -----

module {
  shard.grid @tp(shape = 2)

  func.func @d15_input_residency_stays_valid(%partial: tensor<4xf32>) {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %l1 = stor.localize %global to %sharding rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %in0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %in1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %u1 = stor.unpack %in1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %c0 = shard.all_reduce %u0 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %c1 = shard.all_reduce %u1 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %out0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %c0 into %out0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %c1 into %out1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    %again = stor.unpack %in0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %reduced = stor.unpack %out0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    return
  }
}

// -----

module {
  shard.grid @left(shape = 2)
  shard.grid @right(shape = 2)

  func.func @d17_two_meshes(%partial: tensor<4xf32>) {
    %left = shard.sharding @left split_axes = [[]] : !shard.sharding
    %right = shard.sharding @right split_axes = [[]] : !shard.sharding
    %g0 = stor.object : !stor.object<tensor<4xf32>>
    %g1 = stor.object : !stor.object<tensor<4xf32>>
    %a0 = stor.localize %g0 to %left rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %a1 = stor.localize %g0 to %left rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %b0 = stor.localize %g1 to %right rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %b1 = stor.localize %g1 to %right rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %in0 = stor.materialize %a0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %in1 = stor.materialize %a1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %jn0 = stor.materialize %b0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %jn1 = stor.materialize %b1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %in0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %in1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %jn0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %jn1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %u1 = stor.unpack %in1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %v0 = stor.unpack %jn0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %v1 = stor.unpack %jn1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %c0 = shard.all_reduce %u0 on @left grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %c1 = shard.all_reduce %u1 on @left grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %d0 = shard.all_reduce %v0 on @right grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %d1 = shard.all_reduce %v1 on @right grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %out0 = stor.materialize %a0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out1 = stor.materialize %a1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %pout0 = stor.materialize %b0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %pout1 = stor.materialize %b1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %c0 into %out0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %c1 into %out1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %d0 into %pout0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %d1 into %pout1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    return
  }
}

// -----

module {
  shard.grid @tp(shape = 2)

  func.func @d18_nested_concurrent(%partial: tensor<4xf32>) {
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
        %c0 = shard.all_reduce %u0 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
        stor.pack %c0 into %out0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
        %y0 = stor.unpack %out0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
        sched.yield
      }
      %t1 = sched.task {
        stor.pack %partial into %in1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
        %u1 = stor.unpack %in1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
        %c1 = shard.all_reduce %u1 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
        stor.pack %c1 into %out1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
        %y1 = stor.unpack %out1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
        sched.yield
      }
      sched.yield
    }
    return
  }
}
