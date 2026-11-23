// One sched.wait may list one task token per rank. The wait joins only those
// ranks. A path through the other rank's collective edge does not complete
// this rank. This is compiler lowering fidelity, not the host MPI witness.
// RUN: s2c2-opt %s --check-s2c2-hb-d -split-input-file
// RUN: s2c2-opt %s --lower-s2c2-hb-d=async --check-s2c2-hb-d-fidelity=mode=async -split-input-file | FileCheck %s --check-prefix=ASYNC
// RUN: s2c2-opt %s --lower-s2c2-hb-d=sync --check-s2c2-hb-d-fidelity=mode=sync -split-input-file | FileCheck %s --check-prefix=SYNC

// ASYNC-LABEL: func.func @id_wait_two_rank_tokens
// ASYNC: sched.wait {{.*}}, {{.*}} : !sched.token, !sched.token
// ASYNC: shard.all_reduce
// ASYNC: shard.all_reduce
// SYNC-LABEL: func.func @id_wait_two_rank_tokens
// SYNC-NOT: sched.task
// SYNC-NOT: shard.all_reduce
// SYNC: sched.wait
// SYNC: shard.all_reduce
// SYNC: shard.all_reduce
// SYNC-NOT: sched.task

module {
  shard.grid @tp(shape = 2)

  func.func @id_wait_two_rank_tokens(%partial: tensor<4xf32>) {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %l1 = stor.localize %global to %sharding rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %t0 = sched.task {
      stor.pack %partial into %in0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
      sched.yield
    }
    %t1 = sched.task {
      stor.pack %partial into %in1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
      sched.yield
    }
    sched.wait %t0, %t1 : !sched.token, !sched.token
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %u1 = stor.unpack %in1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %c0 = shard.all_reduce %u0 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %c1 = shard.all_reduce %u1 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    stor.pack %c0 into %out0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %c1 into %out1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    %y = stor.unpack %out0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    return
  }
}

// -----

// Rank 1's input is already packed outside its task. Waiting only for rank 0
// must not move rank 1, and must not be required to.

module {
  shard.grid @tp(shape = 2)

  func.func @id_wait_one_rank_keeps_other(%partial: tensor<4xf32>) {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %l1 = stor.localize %global to %sharding rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %side = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %in1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    %t0 = sched.task {
      stor.pack %partial into %in0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
      sched.yield
    }
    %t1 = sched.task {
      stor.pack %partial into %side : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
      sched.yield
    }
    sched.wait %t0 : !sched.token
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %u1 = stor.unpack %in1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %c0 = shard.all_reduce %u0 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %c1 = shard.all_reduce %u1 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    stor.pack %c0 into %out0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %c1 into %out1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    %y = stor.unpack %out0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    return
  }
}
