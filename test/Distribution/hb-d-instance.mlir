// Two all-reduces on one mesh are two instances. Their cross-rank
// edges stay inside each callsite.
// RUN: s2c2-opt %s --check-s2c2-hb-d 2>&1 | FileCheck %s
// RUN: s2c2-opt %s --check-s2c2-execution

// CHECK: hb-d @id_two_allreduces instances=2 cross-instance-edges=0

module {
  shard.grid @tp(shape = 2)

  func.func @id_two_allreduces(%left: tensor<4xf32>, %right: tensor<4xf32>) {
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
    %aout0 = stor.materialize %a0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %aout1 = stor.materialize %a1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %bout0 = stor.materialize %b0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %bout1 = stor.materialize %b1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %left into %ain0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %left into %ain1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %right into %bin0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %right into %bin1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
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
    %y = stor.unpack %aout0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    return
  }
}
