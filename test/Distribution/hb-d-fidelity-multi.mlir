// Multi-mesh, multi-collective lowering. HB_D source stays inside the
// target, and each instance keeps its participants and result object.
// RUN: s2c2-opt %s --lower-s2c2-hb-d=async --check-s2c2-hb-d-fidelity=mode=async -split-input-file | FileCheck %s --check-prefix=ASYNC
// RUN: s2c2-opt %s --lower-s2c2-hb-d=sync --check-s2c2-hb-d-fidelity=mode=sync -split-input-file | FileCheck %s --check-prefix=SYNC

// ASYNC-LABEL: func.func @id_multi_mesh_fidelity
// ASYNC-COUNT-4: on @tp
// ASYNC-COUNT-2: on @dp
// ASYNC-COUNT-6: stor.pack
// SYNC-LABEL: func.func @id_multi_mesh_fidelity
// SYNC-NOT: sched.task
// SYNC-COUNT-4: on @tp
// SYNC-COUNT-2: on @dp
// SYNC-COUNT-6: stor.pack

module {
  shard.grid @tp(shape = 2)
  shard.grid @dp(shape = 2)

  func.func @id_multi_mesh_fidelity(%acts: tensor<4xf32>, %grads: tensor<4xf32>, %extra: tensor<4xf32>) -> tensor<4xf32> {
    %tp_shard = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %dp_shard = shard.sharding @dp split_axes = [[]] : !shard.sharding
    %ga = stor.object : !stor.object<tensor<4xf32>>
    %gb = stor.object : !stor.object<tensor<4xf32>>
    %gd = stor.object : !stor.object<tensor<4xf32>>
    %a0 = stor.localize %ga to %tp_shard rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %a1 = stor.localize %ga to %tp_shard rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %b0 = stor.localize %gb to %tp_shard rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %b1 = stor.localize %gb to %tp_shard rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %d0 = stor.localize %gd to %dp_shard rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %d1 = stor.localize %gd to %dp_shard rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %ain0 = stor.materialize %a0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %ain1 = stor.materialize %a1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %bin0 = stor.materialize %b0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %bin1 = stor.materialize %b1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %din0 = stor.materialize %d0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %din1 = stor.materialize %d1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %aout0 = stor.materialize %a0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %aout1 = stor.materialize %a1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %bout0 = stor.materialize %b0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %bout1 = stor.materialize %b1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %dout0 = stor.materialize %d0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %dout1 = stor.materialize %d1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %acts into %ain0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %acts into %ain1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %extra into %bin0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %extra into %bin1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %grads into %din0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %grads into %din1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    %ua0 = stor.unpack %ain0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %ua1 = stor.unpack %ain1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %ub0 = stor.unpack %bin0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %ub1 = stor.unpack %bin1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %ud0 = stor.unpack %din0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %ud1 = stor.unpack %din1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %ca0 = shard.all_reduce %ua0 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %ca1 = shard.all_reduce %ua1 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %cb0 = shard.all_reduce %ub0 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %cb1 = shard.all_reduce %ub1 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %cd0 = shard.all_reduce %ud0 on @dp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %cd1 = shard.all_reduce %ud1 on @dp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    stor.pack %ca0 into %aout0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %ca1 into %aout1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %cb0 into %bout0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %cb1 into %bout1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %cd0 into %dout0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %cd1 into %dout1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    %y = stor.unpack %aout0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    return %y : tensor<4xf32>
  }
}
