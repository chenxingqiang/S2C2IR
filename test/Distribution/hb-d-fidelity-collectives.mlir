// all-gather and reduce-scatter keep participants, input packs, and result
// identity through async and sync lowering. This is compiler fidelity, not
// the host MPI witness.
// RUN: s2c2-opt %s --lower-s2c2-hb-d=async --check-s2c2-hb-d-fidelity=mode=async -split-input-file | FileCheck %s --check-prefix=ASYNC
// RUN: s2c2-opt %s --lower-s2c2-hb-d=sync --check-s2c2-hb-d-fidelity=mode=sync -split-input-file | FileCheck %s --check-prefix=SYNC
// An empty task on one line, then a free collective, must not match ASYNC.
// RUN: not FileCheck --check-prefix=ASYNC --input-file=%S/Inputs/async-collective-escapes-task.mlir %s

// ASYNC-LABEL: func.func @id_all_gather_fidelity
// ASYNC: stor.localize {{.*}} rank = 0
// ASYNC: stor.localize {{.*}} rank = 1
// ASYNC: sched.task
// ASYNC-NEXT: shard.all_gather {{.*}} on @tp grid_axes = {{\[0\]}} gather_axis = 0
// ASYNC-NEXT: sched.yield
// ASYNC-NEXT: {{^ *\}$}}
// ASYNC: sched.task
// ASYNC-NEXT: shard.all_gather {{.*}} on @tp grid_axes = {{\[0\]}} gather_axis = 0
// ASYNC-NEXT: sched.yield
// ASYNC-NEXT: {{^ *\}$}}
// ASYNC: stor.pack
// SYNC-LABEL: func.func @id_all_gather_fidelity
// SYNC-NOT: sched.task
// SYNC: stor.localize {{.*}} rank = 0
// SYNC-NOT: sched.task
// SYNC: stor.localize {{.*}} rank = 1
// SYNC-NOT: sched.task
// SYNC: shard.all_gather {{.*}} on @tp grid_axes = {{\[0\]}} gather_axis = 0
// SYNC-NOT: sched.task
// SYNC: shard.all_gather {{.*}} on @tp grid_axes = {{\[0\]}} gather_axis = 0
// SYNC-NOT: sched.task
// SYNC: return

module {
  shard.grid @tp(shape = 2)

  func.func @id_all_gather_fidelity(%tile: tensor<2x8xf32>) {
    %sharded = shard.sharding @tp split_axes = [[0]] : !shard.sharding
    %replicated = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4x8xf32>>
    %gathered = stor.object : !stor.object<tensor<4x8xf32>>
    %l0 = stor.localize %global to %sharded rank = 0 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<2x8xf32>>
    %l1 = stor.localize %global to %sharded rank = 1 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<2x8xf32>>
    %g0 = stor.localize %gathered to %replicated rank = 0 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<4x8xf32>>
    %g1 = stor.localize %gathered to %replicated rank = 1 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<4x8xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<2x8xf32>> -> !stor.buffer<tensor<2x8xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<2x8xf32>> -> !stor.buffer<tensor<2x8xf32>, hbm>
    stor.pack %tile into %in0 : tensor<2x8xf32>, !stor.buffer<tensor<2x8xf32>, hbm>
    stor.pack %tile into %in1 : tensor<2x8xf32>, !stor.buffer<tensor<2x8xf32>, hbm>
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<2x8xf32>, hbm> -> tensor<2x8xf32>
    %u1 = stor.unpack %in1 : !stor.buffer<tensor<2x8xf32>, hbm> -> tensor<2x8xf32>
    %c0 = shard.all_gather %u0 on @tp grid_axes = [0] gather_axis = 0 : tensor<2x8xf32> -> tensor<4x8xf32>
    %c1 = shard.all_gather %u1 on @tp grid_axes = [0] gather_axis = 0 : tensor<2x8xf32> -> tensor<4x8xf32>
    %out0 = stor.materialize %g0 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    %out1 = stor.materialize %g1 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %c0 into %out0 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %c1 into %out1 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    %y = stor.unpack %out0 : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    return
  }
}

// -----

// ASYNC-LABEL: func.func @id_reduce_scatter_fidelity
// ASYNC: stor.localize {{.*}} rank = 0
// ASYNC: stor.localize {{.*}} rank = 1
// ASYNC: sched.task
// ASYNC-NEXT: shard.reduce_scatter {{.*}} on @tp grid_axes = {{\[0\]}} scatter_axis = 0
// ASYNC-NEXT: sched.yield
// ASYNC-NEXT: {{^ *\}$}}
// ASYNC: sched.task
// ASYNC-NEXT: shard.reduce_scatter {{.*}} on @tp grid_axes = {{\[0\]}} scatter_axis = 0
// ASYNC-NEXT: sched.yield
// ASYNC-NEXT: {{^ *\}$}}
// ASYNC: stor.pack
// SYNC-LABEL: func.func @id_reduce_scatter_fidelity
// SYNC-NOT: sched.task
// SYNC: stor.localize {{.*}} rank = 0
// SYNC-NOT: sched.task
// SYNC: stor.localize {{.*}} rank = 1
// SYNC-NOT: sched.task
// SYNC: shard.reduce_scatter {{.*}} on @tp grid_axes = {{\[0\]}} scatter_axis = 0
// SYNC-NOT: sched.task
// SYNC: shard.reduce_scatter {{.*}} on @tp grid_axes = {{\[0\]}} scatter_axis = 0
// SYNC-NOT: sched.task
// SYNC: return

module {
  shard.grid @tp(shape = 2)

  func.func @id_reduce_scatter_fidelity(%partial: tensor<4x8xf32>) {
    %replicated = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %sharded = shard.sharding @tp split_axes = [[0]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4x8xf32>>
    %scattered = stor.object : !stor.object<tensor<4x8xf32>>
    %l0 = stor.localize %global to %replicated rank = 0 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<4x8xf32>>
    %l1 = stor.localize %global to %replicated rank = 1 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<4x8xf32>>
    %s0 = stor.localize %scattered to %sharded rank = 0 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<2x8xf32>>
    %s1 = stor.localize %scattered to %sharded rank = 1 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<2x8xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %partial into %in0 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %partial into %in1 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    %u1 = stor.unpack %in1 : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    %c0 = shard.reduce_scatter %u0 on @tp grid_axes = [0] scatter_axis = 0 : tensor<4x8xf32> -> tensor<2x8xf32>
    %c1 = shard.reduce_scatter %u1 on @tp grid_axes = [0] scatter_axis = 0 : tensor<4x8xf32> -> tensor<2x8xf32>
    %out0 = stor.materialize %s0 : !stor.object<tensor<2x8xf32>> -> !stor.buffer<tensor<2x8xf32>, hbm>
    %out1 = stor.materialize %s1 : !stor.object<tensor<2x8xf32>> -> !stor.buffer<tensor<2x8xf32>, hbm>
    stor.pack %c0 into %out0 : tensor<2x8xf32>, !stor.buffer<tensor<2x8xf32>, hbm>
    stor.pack %c1 into %out1 : tensor<2x8xf32>, !stor.buffer<tensor<2x8xf32>, hbm>
    %y = stor.unpack %out0 : !stor.buffer<tensor<2x8xf32>, hbm> -> tensor<2x8xf32>
    return
  }
}
