// The mesh has two ranks. One rank enters. MPI is not called.
// REQUIRES: mpi
// RUN: not mpirun --allow-run-as-root --bind-to none -n 2 s2c2-dist-runtime %s 2>&1 | FileCheck %s

// CHECK: error: runtime participants do not match the mesh

module {
  shard.grid @g(shape = 2)

  func.func @runtime_dropped_rank(%partial: tensor<4xf32>) {
    %sharding = shard.sharding @g split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %in0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %t0, %c0 = sched.task -> tensor<4xf32> {
      %c = shard.all_reduce %u0 on @g grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
      sched.yield %c : tensor<4xf32>
    }
    stor.pack %c0 into %out0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    return
  }
}
