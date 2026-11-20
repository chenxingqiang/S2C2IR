// Host OpenMPI witness. Each (mesh, callsite) is its own MPI call.
// The payloads are witness scalars, not an end-to-end tensor runtime.
// REQUIRES: mpi
// RUN: mpirun --allow-run-as-root --bind-to none -n 2 s2c2-dist-runtime %s | FileCheck %s

// CHECK: runtime mpi
// CHECK: real-device no
// CHECK: tensor-runtime no
// CHECK: func @id_multi_mesh_witness collective shard.all_reduce participants=0,1 token=!sched.token hb-d=satisfied mpi=ok instance mesh=@tp callsite=0 allreduce-sum=3
// CHECK: func @id_multi_mesh_witness collective shard.all_gather participants=0,1 token=!sched.token hb-d=satisfied mpi=ok instance mesh=@tp callsite=1 allgather-order=1,2
// CHECK: func @id_multi_mesh_witness collective shard.reduce_scatter participants=0,1 token=!sched.token hb-d=satisfied mpi=ok instance mesh=@dp callsite=0 reducescatter-shard=3

module {
  shard.grid @tp(shape = 2)
  shard.grid @dp(shape = 2)

  func.func @id_multi_mesh_witness(%partial: tensor<4xf32>, %tile: tensor<2xf32>, %grads: tensor<4xf32>) -> tensor<4xf32> {
    %rep = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %sharded = shard.sharding @tp split_axes = [[0]] : !shard.sharding
    %dp_rep = shard.sharding @dp split_axes = [[]] : !shard.sharding
    %dp_sharded = shard.sharding @dp split_axes = [[0]] : !shard.sharding
    %ga = stor.object : !stor.object<tensor<4xf32>>
    %gg = stor.object : !stor.object<tensor<4xf32>>
    %gathered = stor.object : !stor.object<tensor<4xf32>>
    %gs = stor.object : !stor.object<tensor<4xf32>>
    %scattered = stor.object : !stor.object<tensor<4xf32>>
    %a0 = stor.localize %ga to %rep rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %a1 = stor.localize %ga to %rep rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %g0 = stor.localize %gg to %sharded rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<2xf32>>
    %g1 = stor.localize %gg to %sharded rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<2xf32>>
    %q0 = stor.localize %gathered to %rep rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %q1 = stor.localize %gathered to %rep rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %s0 = stor.localize %gs to %dp_rep rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %s1 = stor.localize %gs to %dp_rep rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %t0 = stor.localize %scattered to %dp_sharded rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<2xf32>>
    %t1 = stor.localize %scattered to %dp_sharded rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<2xf32>>
    %ain0 = stor.materialize %a0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %ain1 = stor.materialize %a1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %gin0 = stor.materialize %g0 : !stor.object<tensor<2xf32>> -> !stor.buffer<tensor<2xf32>, hbm>
    %gin1 = stor.materialize %g1 : !stor.object<tensor<2xf32>> -> !stor.buffer<tensor<2xf32>, hbm>
    %sin0 = stor.materialize %s0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %sin1 = stor.materialize %s1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %aout0 = stor.materialize %a0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %aout1 = stor.materialize %a1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %qout0 = stor.materialize %q0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %qout1 = stor.materialize %q1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %tout0 = stor.materialize %t0 : !stor.object<tensor<2xf32>> -> !stor.buffer<tensor<2xf32>, hbm>
    %tout1 = stor.materialize %t1 : !stor.object<tensor<2xf32>> -> !stor.buffer<tensor<2xf32>, hbm>
    stor.pack %partial into %ain0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %ain1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %tile into %gin0 : tensor<2xf32>, !stor.buffer<tensor<2xf32>, hbm>
    stor.pack %tile into %gin1 : tensor<2xf32>, !stor.buffer<tensor<2xf32>, hbm>
    stor.pack %grads into %sin0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %grads into %sin1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    %ua0 = stor.unpack %ain0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %ua1 = stor.unpack %ain1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %ug0 = stor.unpack %gin0 : !stor.buffer<tensor<2xf32>, hbm> -> tensor<2xf32>
    %ug1 = stor.unpack %gin1 : !stor.buffer<tensor<2xf32>, hbm> -> tensor<2xf32>
    %us0 = stor.unpack %sin0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %us1 = stor.unpack %sin1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %ta0, %ca0 = sched.task -> tensor<4xf32> {
      %c = shard.all_reduce %ua0 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
      sched.yield %c : tensor<4xf32>
    }
    %ta1, %ca1 = sched.task -> tensor<4xf32> {
      %c = shard.all_reduce %ua1 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
      sched.yield %c : tensor<4xf32>
    }
    %tg0, %cg0 = sched.task -> tensor<4xf32> {
      %c = shard.all_gather %ug0 on @tp grid_axes = [0] gather_axis = 0 : tensor<2xf32> -> tensor<4xf32>
      sched.yield %c : tensor<4xf32>
    }
    %tg1, %cg1 = sched.task -> tensor<4xf32> {
      %c = shard.all_gather %ug1 on @tp grid_axes = [0] gather_axis = 0 : tensor<2xf32> -> tensor<4xf32>
      sched.yield %c : tensor<4xf32>
    }
    %ts0, %cs0 = sched.task -> tensor<2xf32> {
      %c = shard.reduce_scatter %us0 on @dp grid_axes = [0] scatter_axis = 0 : tensor<4xf32> -> tensor<2xf32>
      sched.yield %c : tensor<2xf32>
    }
    %ts1, %cs1 = sched.task -> tensor<2xf32> {
      %c = shard.reduce_scatter %us1 on @dp grid_axes = [0] scatter_axis = 0 : tensor<4xf32> -> tensor<2xf32>
      sched.yield %c : tensor<2xf32>
    }
    stor.pack %ca0 into %aout0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %ca1 into %aout1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %cg0 into %qout0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %cg1 into %qout1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %cs0 into %tout0 : tensor<2xf32>, !stor.buffer<tensor<2xf32>, hbm>
    stor.pack %cs1 into %tout1 : tensor<2xf32>, !stor.buffer<tensor<2xf32>, hbm>
    %y = stor.unpack %aout0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    return %y : tensor<4xf32>
  }
}
