// Both ranks enter. A result read is not HB_D-after the completion token.
// MPI is not called. The failure is the event order, not an API status.
// RUN: not mpirun --allow-run-as-root --bind-to none -n 2 s2c2-dist-runtime %s 2>&1 | FileCheck %s

// CHECK: error: runtime completion is not HB_D-before the result read

module {
  shard.grid @g(shape = 2)

  func.func @runtime_hb_not_met(%partial: tensor<4xf32>) {
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
    sched.concurrent {
      %t0, %c0 = sched.task -> tensor<4xf32> {
        %u0 = stor.unpack %in0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
        %c = shard.all_reduce %u0 on @g grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
        stor.pack %c into %out0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
        sched.yield %c : tensor<4xf32>
      }
      %t1, %c1 = sched.task -> tensor<4xf32> {
        %early = stor.unpack %out0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
        %u1 = stor.unpack %in1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
        %c = shard.all_reduce %u1 on @g grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
        stor.pack %c into %out1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
        sched.yield %c : tensor<4xf32>
      }
      sched.yield
    }
    return
  }
}
