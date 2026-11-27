// Not a lit test. Each collective is the next line after an empty task, so
// the two are adjacent, but the collective is outside the task region.
// hb-d-fidelity-collectives.mlir FileChecks this with --check-prefix=ASYNC
// and expects that check to fail.

func.func @id_all_gather_fidelity() {
  stor.localize %0 to %s rank = 0
  stor.localize %0 to %s rank = 1
  %t0 = sched.task { sched.yield }
  %c0 = shard.all_gather %u on @tp grid_axes = [0] gather_axis = 0 : tensor<2x8xf32> -> tensor<4x8xf32>
  stor.pack %c0 into %b : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
  %t1 = sched.task { sched.yield }
  %c1 = shard.all_gather %u on @tp grid_axes = [0] gather_axis = 0 : tensor<2x8xf32> -> tensor<4x8xf32>
  stor.pack %c1 into %b : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
  return
}

func.func @id_reduce_scatter_fidelity() {
  stor.localize %0 to %s rank = 0
  stor.localize %0 to %s rank = 1
  %t0 = sched.task { sched.yield }
  %c0 = shard.reduce_scatter %u on @tp grid_axes = [0] scatter_axis = 0 : tensor<4x8xf32> -> tensor<2x8xf32>
  stor.pack %c0 into %b : tensor<2x8xf32>, !stor.buffer<tensor<2x8xf32>, hbm>
  %t1 = sched.task { sched.yield }
  %c1 = shard.reduce_scatter %u on @tp grid_axes = [0] scatter_axis = 0 : tensor<4x8xf32> -> tensor<2x8xf32>
  stor.pack %c1 into %b : tensor<2x8xf32>, !stor.buffer<tensor<2x8xf32>, hbm>
  return
}
