// Host MPI, not a device. No GPU and no NPU. Completion is !sched.token.
// A trace timestamp is not the witness. RUN uses two host ranks.
// RUN: mpirun --allow-run-as-root --bind-to none -n 2 s2c2-dist-runtime %s | FileCheck %s

// CHECK: runtime mpi
// CHECK: real-device no
// CHECK: device-note host MPI has no GPU or NPU; completion is not a trace timestamp
// CHECK: hb-source ir-hb-d
// CHECK: api-only=rejected
// CHECK: func @d21_runtime_all_reduce collective shard.all_reduce participants=0,1 token=!sched.token hb-d=satisfied mpi=ok
// CHECK: func @d22_runtime_all_gather collective shard.all_gather participants=0,1 token=!sched.token hb-d=satisfied mpi=ok
// CHECK: func @d23_runtime_reduce_scatter collective shard.reduce_scatter participants=0,1 token=!sched.token hb-d=satisfied mpi=ok

module {
  shard.grid @g(shape = 2)

  func.func @d21_runtime_all_reduce(%partial: tensor<4xf32>) -> tensor<4xf32> {
    %sharding = shard.sharding @g split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %l1 = stor.localize %global to %sharding rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %in0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %in1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %u1 = stor.unpack %in1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %t0, %c0 = sched.task -> tensor<4xf32> {
      %c = shard.all_reduce %u0 on @g grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
      sched.yield %c : tensor<4xf32>
    }
    %t1, %c1 = sched.task -> tensor<4xf32> {
      %c = shard.all_reduce %u1 on @g grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
      sched.yield %c : tensor<4xf32>
    }
    stor.pack %c0 into %out0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %c1 into %out1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    %y = stor.unpack %out0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    return %y : tensor<4xf32>
  }

  func.func @d22_runtime_all_gather(%tile: tensor<2xf32>) -> tensor<4xf32> {
    %sharded = shard.sharding @g split_axes = [[0]] : !shard.sharding
    %replicated = shard.sharding @g split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4xf32>>
    %gathered = stor.object : !stor.object<tensor<4xf32>>
    %l0 = stor.localize %global to %sharded rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<2xf32>>
    %l1 = stor.localize %global to %sharded rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<2xf32>>
    %g0 = stor.localize %gathered to %replicated rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %g1 = stor.localize %gathered to %replicated rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<2xf32>> -> !stor.buffer<tensor<2xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<2xf32>> -> !stor.buffer<tensor<2xf32>, hbm>
    %out0 = stor.materialize %g0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out1 = stor.materialize %g1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %tile into %in0 : tensor<2xf32>, !stor.buffer<tensor<2xf32>, hbm>
    stor.pack %tile into %in1 : tensor<2xf32>, !stor.buffer<tensor<2xf32>, hbm>
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<2xf32>, hbm> -> tensor<2xf32>
    %u1 = stor.unpack %in1 : !stor.buffer<tensor<2xf32>, hbm> -> tensor<2xf32>
    %t0, %c0 = sched.task -> tensor<4xf32> {
      %c = shard.all_gather %u0 on @g grid_axes = [0] gather_axis = 0 : tensor<2xf32> -> tensor<4xf32>
      sched.yield %c : tensor<4xf32>
    }
    %t1, %c1 = sched.task -> tensor<4xf32> {
      %c = shard.all_gather %u1 on @g grid_axes = [0] gather_axis = 0 : tensor<2xf32> -> tensor<4xf32>
      sched.yield %c : tensor<4xf32>
    }
    stor.pack %c0 into %out0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %c1 into %out1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    %y = stor.unpack %out0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    return %y : tensor<4xf32>
  }

  func.func @d23_runtime_reduce_scatter(%partial: tensor<4xf32>) -> tensor<2xf32> {
    %replicated = shard.sharding @g split_axes = [[]] : !shard.sharding
    %sharded = shard.sharding @g split_axes = [[0]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4xf32>>
    %scattered = stor.object : !stor.object<tensor<4xf32>>
    %l0 = stor.localize %global to %replicated rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %l1 = stor.localize %global to %replicated rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %s0 = stor.localize %scattered to %sharded rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<2xf32>>
    %s1 = stor.localize %scattered to %sharded rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<2xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out0 = stor.materialize %s0 : !stor.object<tensor<2xf32>> -> !stor.buffer<tensor<2xf32>, hbm>
    %out1 = stor.materialize %s1 : !stor.object<tensor<2xf32>> -> !stor.buffer<tensor<2xf32>, hbm>
    stor.pack %partial into %in0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %in1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %u1 = stor.unpack %in1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %t0, %c0 = sched.task -> tensor<2xf32> {
      %c = shard.reduce_scatter %u0 on @g grid_axes = [0] scatter_axis = 0 : tensor<4xf32> -> tensor<2xf32>
      sched.yield %c : tensor<2xf32>
    }
    %t1, %c1 = sched.task -> tensor<2xf32> {
      %c = shard.reduce_scatter %u1 on @g grid_axes = [0] scatter_axis = 0 : tensor<4xf32> -> tensor<2xf32>
      sched.yield %c : tensor<2xf32>
    }
    stor.pack %c0 into %out0 : tensor<2xf32>, !stor.buffer<tensor<2xf32>, hbm>
    stor.pack %c1 into %out1 : tensor<2xf32>, !stor.buffer<tensor<2xf32>, hbm>
    %y = stor.unpack %out0 : !stor.buffer<tensor<2xf32>, hbm> -> tensor<2xf32>
    return %y : tensor<2xf32>
  }
}
