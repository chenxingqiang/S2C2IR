// Dynamic control flow stays dynamic after sync. Hoisting either branch, or
// the body of a loop that may run zero times, fails these checks.
// RUN: s2c2-opt %s --lower-s2c2-hb-d=async --check-s2c2-hb-d-fidelity=mode=async -split-input-file | FileCheck %s --check-prefix=ASYNC
// RUN: s2c2-opt %s --lower-s2c2-hb-d=sync --check-s2c2-hb-d-fidelity=mode=sync -split-input-file | FileCheck %s --check-prefix=SYNC
// RUN: s2c2-opt %s --lower-s2c2-hb-d=async -split-input-file | s2c2-opt -split-input-file --lower-s2c2-hb-d=sync --check-s2c2-hb-d-fidelity=mode=sync | FileCheck %s --check-prefix=PIPE

// ASYNC-LABEL: func.func @id_sync_dynamic_if
// ASYNC: scf.if
// ASYNC: shard.all_reduce
// ASYNC: shard.all_reduce
// ASYNC: else
// ASYNC-NOT: shard.all_reduce
// SYNC-LABEL: func.func @id_sync_dynamic_if
// SYNC: scf.if
// SYNC: shard.all_reduce
// SYNC: shard.all_reduce
// SYNC: else
// SYNC-NOT: shard.all_reduce
// SYNC-NOT: sched.task
// PIPE-LABEL: func.func @id_sync_dynamic_if
// PIPE: scf.if
// PIPE: shard.all_reduce
// PIPE: shard.all_reduce
// PIPE: else
// PIPE-NOT: shard.all_reduce
// PIPE-NOT: sched.task

module {
  shard.grid @tp(shape = 2)

  func.func @id_sync_dynamic_if(%partial: tensor<4xf32>, %cond: i1) {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %l1 = stor.localize %global to %sharding rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    scf.if %cond {
      stor.pack %partial into %in0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
      stor.pack %partial into %in1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
      %u0 = stor.unpack %in0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
      %u1 = stor.unpack %in1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
      %r0 = shard.all_reduce %u0 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
      %r1 = shard.all_reduce %u1 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
      stor.pack %r0 into %out0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
      stor.pack %r1 into %out1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
      scf.yield
    } else {
      scf.yield
    }
    return
  }
}

// -----

// ASYNC-LABEL: func.func @id_sync_dynamic_for
// ASYNC: scf.for
// ASYNC: shard.all_reduce
// ASYNC: shard.all_reduce
// ASYNC: stor.pack
// ASYNC: }
// ASYNC-NEXT: return
// SYNC-LABEL: func.func @id_sync_dynamic_for
// SYNC: scf.for
// SYNC-NOT: sched.task
// SYNC: shard.all_reduce
// SYNC-NOT: sched.task
// SYNC: shard.all_reduce
// SYNC-NOT: sched.task
// SYNC: }
// SYNC-NEXT: return
// PIPE-LABEL: func.func @id_sync_dynamic_for
// PIPE: scf.for
// PIPE-NOT: sched.task
// PIPE: shard.all_reduce
// PIPE-NOT: sched.task
// PIPE: shard.all_reduce
// PIPE-NOT: sched.task
// PIPE: }
// PIPE-NEXT: return

module {
  shard.grid @tp(shape = 2)

  func.func @id_sync_dynamic_for(%partial: tensor<4xf32>, %bound: index) {
    %sharding = shard.sharding @tp split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4xf32>>
    %l0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %l1 = stor.localize %global to %sharding rank = 1 : !stor.object<tensor<4xf32>>, !shard.sharding -> !stor.object<tensor<4xf32>>
    %in0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %in1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out0 = stor.materialize %l0 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %out1 = stor.materialize %l1 : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    scf.for %i = %c0 to %bound step %c1 {
      stor.pack %partial into %in0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
      stor.pack %partial into %in1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
      %u0 = stor.unpack %in0 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
      %u1 = stor.unpack %in1 : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
      %r0 = shard.all_reduce %u0 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
      %r1 = shard.all_reduce %u1 on @tp grid_axes = [0] : tensor<4xf32> -> tensor<4xf32>
      stor.pack %r0 into %out0 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
      stor.pack %r1 into %out1 : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
      scf.yield
    }
    return
  }
}
