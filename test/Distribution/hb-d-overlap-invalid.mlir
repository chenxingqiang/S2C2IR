// Each overlap lane still writes some same-rank buffer. The consumer of
// the lane whose pack was removed must be rejected.
// RUN: s2c2-opt %s --check-s2c2-hb-d -split-input-file -verify-diagnostics

module {
  shard.grid @tp(shape = 2)

  func.func @id_overlap_drop_compute(%partial: tensor<4xf32>) {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %ga = stor.object : !stor.object<tensor<4xf32>>
    %gb = stor.object : !stor.object<tensor<4xf32>>
    %a0 = stor.localize %ga to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %a1 = stor.localize %ga to %sharding rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %b0 = stor.localize %gb to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %b1 = stor.localize %gb to %sharding rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %ain0 = stor.materialize %a0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %ain1 = stor.materialize %a1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %bin0 = stor.materialize %b0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %bin1 = stor.materialize %b1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %side = stor.materialize %a0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %aout0 = stor.materialize %a0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %aout1 = stor.materialize %a1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %bout0 = stor.materialize %b0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %bout1 = stor.materialize %b1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %ain1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %bin1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    sched.overlap {
      stor.pack %partial into %side : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
      sched.yield
    } {
      stor.pack %partial into %bin0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
      sched.yield
    }
    // expected-error @+1 {{read of residency is undefined: no happens-before from a validity-establishing write}}
    %ua0 = stor.unpack %ain0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %ua1 = stor.unpack %ain1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %ub0 = stor.unpack %bin0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %ub1 = stor.unpack %bin1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %ca0 = shard.all_reduce %ua0 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %ca1 = shard.all_reduce %ua1 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %cb0 = shard.all_reduce %ub0 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %cb1 = shard.all_reduce %ub1 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    stor.pack %ca0 into %aout0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %ca1 into %aout1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %cb0 into %bout0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %cb1 into %bout1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    return
  }
}

// -----

module {
  shard.grid @tp(shape = 2)

  func.func @id_overlap_drop_communicate(%partial: tensor<4xf32>) {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %ga = stor.object : !stor.object<tensor<4xf32>>
    %gb = stor.object : !stor.object<tensor<4xf32>>
    %a0 = stor.localize %ga to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %a1 = stor.localize %ga to %sharding rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %b0 = stor.localize %gb to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %b1 = stor.localize %gb to %sharding rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %ain0 = stor.materialize %a0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %ain1 = stor.materialize %a1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %bin0 = stor.materialize %b0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %bin1 = stor.materialize %b1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %side = stor.materialize %b0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %aout0 = stor.materialize %a0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %aout1 = stor.materialize %a1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %bout0 = stor.materialize %b0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %bout1 = stor.materialize %b1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %ain1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %bin1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    sched.overlap {
      stor.pack %partial into %ain0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
      sched.yield
    } {
      stor.pack %partial into %side : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
      sched.yield
    }
    %ua0 = stor.unpack %ain0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %ua1 = stor.unpack %ain1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    // expected-error @+1 {{read of residency is undefined: no happens-before from a validity-establishing write}}
    %ub0 = stor.unpack %bin0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %ub1 = stor.unpack %bin1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %ca0 = shard.all_reduce %ua0 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %ca1 = shard.all_reduce %ua1 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %cb0 = shard.all_reduce %ub0 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %cb1 = shard.all_reduce %ub1 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    stor.pack %ca0 into %aout0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %ca1 into %aout1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %cb0 into %bout0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %cb1 into %bout1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    return
  }
}
