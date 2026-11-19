// RUN: s2c2-opt %s --lower-s2c2-hb-d=async --check-s2c2-hb-d-fidelity=mode=async -split-input-file | FileCheck %s --check-prefix=ASYNC
// RUN: s2c2-opt %s --lower-s2c2-hb-d=sync --check-s2c2-hb-d-fidelity=mode=sync -split-input-file | FileCheck %s --check-prefix=SYNC

// ASYNC-LABEL: func.func @d01_async_keeps_edges
// ASYNC: stor.localize {{.*}} rank = 0
// ASYNC: stor.localize {{.*}} rank = 1
// ASYNC: sched.task
// ASYNC: shard.all_reduce
// ASYNC: sched.yield
// ASYNC: stor.pack

module {
  shard.grid @tp(shape = 2)

  func.func @d01_async_keeps_edges(%partial: tensor<4x8xf32>, %rhs: tensor<8x4xf32>) -> tensor<4x4xf32> {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4x8xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<4x8xf32>>
    %l1 = stor.localize %global to %sharding rank = 1 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<4x8xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %partial into %in0 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %partial into %in1 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    %u1 = stor.unpack %in1 : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    %c = shard.all_reduce %u0 on @tp grid_axes = [0] : tensor<4x8xf32> -> tensor<4x8xf32>
    %out0 = stor.materialize %l0 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    %out1 = stor.materialize %l1 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %c into %out0 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %c into %out1 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    %reduced = stor.unpack %out0 : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    %y = comp.matmul %reduced, %rhs : tensor<4x8xf32>, tensor<8x4xf32> -> tensor<4x4xf32>
    return %y : tensor<4x4xf32>
  }
}

// -----

// SYNC-LABEL: func.func @d01_sync_is_linear_extension
// SYNC: stor.localize {{.*}} rank = 0
// SYNC: stor.localize {{.*}} rank = 1
// SYNC: shard.all_reduce
// SYNC-NOT: sched.task
// SYNC: stor.pack
// SYNC: return

module {
  shard.grid @tp(shape = 2)

  func.func @d01_sync_is_linear_extension(%partial: tensor<4x8xf32>, %rhs: tensor<8x4xf32>) -> tensor<4x4xf32> {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4x8xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<4x8xf32>>
    %l1 = stor.localize %global to %sharding rank = 1 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<4x8xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %partial into %in0 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %partial into %in1 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    %u0 = stor.unpack %in0 : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    %u1 = stor.unpack %in1 : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    %c = shard.all_reduce %u0 on @tp grid_axes = [0] : tensor<4x8xf32> -> tensor<4x8xf32>
    %out0 = stor.materialize %l0 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    %out1 = stor.materialize %l1 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %c into %out0 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %c into %out1 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    %reduced = stor.unpack %out0 : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    %y = comp.matmul %reduced, %rhs : tensor<4x8xf32>, tensor<8x4xf32> -> tensor<4x4xf32>
    return %y : tensor<4x4xf32>
  }
}

// -----

// ASYNC-LABEL: func.func @mesh_size_one
// ASYNC: stor.localize {{.*}} rank = 0
// ASYNC: shard.all_reduce
// ASYNC-NOT: sched.task
// ASYNC-NOT: rank = 1
// ASYNC: return
// SYNC-LABEL: func.func @mesh_size_one
// SYNC: stor.localize {{.*}} rank = 0
// SYNC: shard.all_reduce
// SYNC-NOT: sched.task
// SYNC-NOT: rank = 1
// SYNC: return

module {
  shard.grid @solo(shape = 1)

  func.func @mesh_size_one(%partial: tensor<4x8xf32>) -> tensor<4x8xf32> {
    %sharding = shard.sharding @solo split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4x8xf32>>
    %local = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<4x8xf32>>
    %in = stor.materialize %local : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %partial into %in : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    %u = stor.unpack %in : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    %c = shard.all_reduce %u on @solo grid_axes = [0] : tensor<4x8xf32> -> tensor<4x8xf32>
    %out = stor.materialize %local : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %c into %out : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    %y = stor.unpack %out : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    return %y : tensor<4x8xf32>
  }
}
