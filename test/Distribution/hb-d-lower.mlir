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
    %c0 = shard.all_reduce %u0 on @tp grid_axes = [0] : tensor<4x8xf32> -> tensor<4x8xf32>
    %c1 = shard.all_reduce %u1 on @tp grid_axes = [0] : tensor<4x8xf32> -> tensor<4x8xf32>
    %out0 = stor.materialize %l0 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    %out1 = stor.materialize %l1 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %c0 into %out0 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %c1 into %out1 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
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
    %c0 = shard.all_reduce %u0 on @tp grid_axes = [0] : tensor<4x8xf32> -> tensor<4x8xf32>
    %c1 = shard.all_reduce %u1 on @tp grid_axes = [0] : tensor<4x8xf32> -> tensor<4x8xf32>
    %out0 = stor.materialize %l0 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    %out1 = stor.materialize %l1 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %c0 into %out0 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %c1 into %out1 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
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

// -----

// ASYNC-LABEL: func.func @d19_nested_schedule
// ASYNC: sched.task
// ASYNC: sched.concurrent
// ASYNC: shard.all_reduce
// ASYNC: shard.all_reduce
// ASYNC: return
// SYNC-LABEL: func.func @d19_nested_schedule
// SYNC: stor.localize {{.*}} rank = 0
// SYNC: stor.localize {{.*}} rank = 1
// SYNC-NOT: sched.concurrent
// SYNC-NOT: sched.task
// SYNC: shard.all_reduce
// SYNC: shard.all_reduce
// SYNC-NOT: sched.concurrent
// SYNC-NOT: sched.task
// SYNC: stor.pack
// SYNC: return

module {
  shard.grid @tp(shape = 2)

  func.func @d19_nested_schedule(%partial: tensor<4x8xf32>) -> tensor<4x8xf32> {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4x8xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<4x8xf32>>
    %l1 = stor.localize %global to %sharding rank = 1 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<4x8xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    %out0 = stor.materialize %l0 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    %out1 = stor.materialize %l1 : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    %outer = sched.task {
      sched.concurrent {
        %t0 = sched.task {
          stor.pack %partial into %in0 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
          %u0 = stor.unpack %in0 : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
          %c0 = shard.all_reduce %u0 on @tp grid_axes = [0] : tensor<4x8xf32> -> tensor<4x8xf32>
          stor.pack %c0 into %out0 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
          sched.yield
        }
        %t1 = sched.task {
          stor.pack %partial into %in1 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
          %u1 = stor.unpack %in1 : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
          %c1 = shard.all_reduce %u1 on @tp grid_axes = [0] : tensor<4x8xf32> -> tensor<4x8xf32>
          stor.pack %c1 into %out1 : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
          sched.yield
        }
        sched.yield
      }
      sched.yield
    }
    %y = stor.unpack %out0 : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    return %y : tensor<4x8xf32>
  }
}

// -----

// ASYNC-LABEL: func.func @d20_two_mesh_collectives
// ASYNC: sched.task
// ASYNC: shard.all_reduce
// ASYNC: shard.all_reduce
// ASYNC: shard.all_reduce
// ASYNC: shard.all_reduce
// ASYNC: return
// SYNC-LABEL: func.func @d20_two_mesh_collectives
// SYNC: shard.all_reduce
// SYNC: shard.all_reduce
// SYNC: shard.all_reduce
// SYNC: shard.all_reduce
// SYNC-NOT: sched.task
// SYNC-NOT: sched.concurrent
// SYNC: return

module {
  shard.grid @tp(shape = 2)
  shard.grid @dp(shape = 2)

  func.func @d20_two_mesh_collectives(%partial: tensor<4xf32>, %grads: tensor<4xf32>) -> tensor<4xf32> {
    %tp_shard = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %dp_shard = shard.sharding @dp split_axes = [[]] : !shard.sharding
    %acts = stor.object : !stor.object<tensor<4xf32>>
    %grad = stor.object : !stor.object<tensor<4xf32>>
    %a0 = stor.localize %acts to %tp_shard rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %a1 = stor.localize %acts to %tp_shard rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %b0 = stor.localize %grad to %dp_shard rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %b1 = stor.localize %grad to %dp_shard rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %ain0 = stor.materialize %a0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %ain1 = stor.materialize %a1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %bin0 = stor.materialize %b0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %bin1 = stor.materialize %b1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %aout0 = stor.materialize %a0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %aout1 = stor.materialize %a1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %bout0 = stor.materialize %b0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %bout1 = stor.materialize %b1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %ain0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %partial into %ain1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %grads into %bin0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %grads into %bin1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    %ua0 = stor.unpack %ain0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %ua1 = stor.unpack %ain1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %ub0 = stor.unpack %bin0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %ub1 = stor.unpack %bin1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    %c0 = shard.all_reduce %ua0 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %c1 = shard.all_reduce %ua1 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %d0 = shard.all_reduce %ub0 on @dp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    %d1 = shard.all_reduce %ub1 on @dp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
    stor.pack %c0 into %aout0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %c1 into %aout1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %d0 into %bout0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    stor.pack %d1 into %bout1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
    %y = stor.unpack %aout0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
    return %y : tensor<4xf32>
  }
}
