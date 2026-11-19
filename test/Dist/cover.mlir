// RUN: s2c2-opt %s | s2c2-opt | FileCheck %s

// Two sharded ranges cover the global tensor, stay in bounds, and do not
// overlap. Endpoints touch: [0, 2) then [2, 4). dist.local ties each shard
// to its local tensor. The global value is the same SSA operand.

module {
  // CHECK-LABEL: func.func @shards_cover_global
  func.func @shards_cover_global() {
    // CHECK: %[[G:.*]] = dist.global : !dist.global<tensor<4xf32>>
    %g = dist.global : !dist.global<tensor<4xf32>>
    // CHECK: %[[S0:.*]] = dist.shard %[[G]] : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [0], tile = [2]>
    %s0 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [0], tile = [2]>
    // CHECK: %[[L0:.*]] = dist.local %[[S0]] : !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [0], tile = [2]> -> !dist.local<tensor<2xf32>>
    %l0 = dist.local %s0 : !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [0], tile = [2]> -> !dist.local<tensor<2xf32>>
    // CHECK: %[[S1:.*]] = dist.shard %[[G]] : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [2], tile = [2]>
    %s1 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [2], tile = [2]>
    // CHECK: %[[L1:.*]] = dist.local %[[S1]] : !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [2], tile = [2]> -> !dist.local<tensor<2xf32>>
    %l1 = dist.local %s1 : !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [2], tile = [2]> -> !dist.local<tensor<2xf32>>
    // CHECK: dist.distribution %[[G]] shards(%[[S0]], %[[S1]]) : (!dist.global<tensor<4xf32>>, !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [0], tile = [2]>, !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [2], tile = [2]>) -> !dist.distribution<tensor<4xf32>, sharded, axis = 0>
    %d = dist.distribution %g shards(%s0, %s1) : (!dist.global<tensor<4xf32>>, !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [0], tile = [2]>, !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [2], tile = [2]>) -> !dist.distribution<tensor<4xf32>, sharded, axis = 0>
    return
  }

  // CHECK-LABEL: func.func @shards_cover_out_of_order
  func.func @shards_cover_out_of_order() {
    %g = dist.global : !dist.global<tensor<4xf32>>
    %s1 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [2], tile = [2]>
    %s0 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [0], tile = [2]>
    %d = dist.distribution %g shards(%s1, %s0) : (!dist.global<tensor<4xf32>>, !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [2], tile = [2]>, !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [0], tile = [2]>) -> !dist.distribution<tensor<4xf32>, sharded, axis = 0>
    return
  }

  // CHECK-LABEL: func.func @shards_cover_uneven
  func.func @shards_cover_uneven() {
    %g = dist.global : !dist.global<tensor<4xf32>>
    %s0 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>
    %s1 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<3xf32>, sharded, axis = 0, offset = [1], tile = [3]>
    %d = dist.distribution %g shards(%s0, %s1) : (!dist.global<tensor<4xf32>>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>, !dist.shard<tensor<3xf32>, sharded, axis = 0, offset = [1], tile = [3]>) -> !dist.distribution<tensor<4xf32>, sharded, axis = 0>
    return
  }

  // CHECK-LABEL: func.func @shards_cover_global_axis0
  func.func @shards_cover_global_axis0() {
    // CHECK: dist.shard {{.*}} -> !dist.shard<tensor<2x8xf32>, sharded, axis = 0, offset = [0, 0], tile = [2, 8]>
    %g = dist.global : !dist.global<tensor<4x8xf32>>
    %s0 = dist.shard %g : !dist.global<tensor<4x8xf32>> -> !dist.shard<tensor<2x8xf32>, sharded, axis = 0, offset = [0, 0], tile = [2, 8]>
    %l0 = dist.local %s0 : !dist.shard<tensor<2x8xf32>, sharded, axis = 0, offset = [0, 0], tile = [2, 8]> -> !dist.local<tensor<2x8xf32>>
    %s1 = dist.shard %g : !dist.global<tensor<4x8xf32>> -> !dist.shard<tensor<2x8xf32>, sharded, axis = 0, offset = [2, 0], tile = [2, 8]>
    %d = dist.distribution %g shards(%s0, %s1) : (!dist.global<tensor<4x8xf32>>, !dist.shard<tensor<2x8xf32>, sharded, axis = 0, offset = [0, 0], tile = [2, 8]>, !dist.shard<tensor<2x8xf32>, sharded, axis = 0, offset = [2, 0], tile = [2, 8]>) -> !dist.distribution<tensor<4x8xf32>, sharded, axis = 0>
    return
  }

  // CHECK-LABEL: func.func @shards_cover_axis1
  func.func @shards_cover_axis1() {
    %g = dist.global : !dist.global<tensor<4x8xf32>>
    %s0 = dist.shard %g : !dist.global<tensor<4x8xf32>> -> !dist.shard<tensor<4x4xf32>, sharded, axis = 1, offset = [0, 0], tile = [4, 4]>
    %s1 = dist.shard %g : !dist.global<tensor<4x8xf32>> -> !dist.shard<tensor<4x4xf32>, sharded, axis = 1, offset = [0, 4], tile = [4, 4]>
    %d = dist.distribution %g shards(%s0, %s1) : (!dist.global<tensor<4x8xf32>>, !dist.shard<tensor<4x4xf32>, sharded, axis = 1, offset = [0, 0], tile = [4, 4]>, !dist.shard<tensor<4x4xf32>, sharded, axis = 1, offset = [0, 4], tile = [4, 4]>) -> !dist.distribution<tensor<4x8xf32>, sharded, axis = 1>
    return
  }

  // CHECK-LABEL: func.func @replicated_copies
  func.func @replicated_copies() {
    // CHECK: !dist.shard<tensor<4x8xf32>, replicated, axis = -1, offset = [0, 0], tile = [4, 8]>
    %g = dist.global : !dist.global<tensor<4x8xf32>>
    %s0 = dist.shard %g : !dist.global<tensor<4x8xf32>> -> !dist.shard<tensor<4x8xf32>, replicated, axis = -1, offset = [0, 0], tile = [4, 8]>
    %l0 = dist.local %s0 : !dist.shard<tensor<4x8xf32>, replicated, axis = -1, offset = [0, 0], tile = [4, 8]> -> !dist.local<tensor<4x8xf32>>
    %s1 = dist.shard %g : !dist.global<tensor<4x8xf32>> -> !dist.shard<tensor<4x8xf32>, replicated, axis = -1, offset = [0, 0], tile = [4, 8]>
    %d = dist.distribution %g shards(%s0, %s1) : (!dist.global<tensor<4x8xf32>>, !dist.shard<tensor<4x8xf32>, replicated, axis = -1, offset = [0, 0], tile = [4, 8]>, !dist.shard<tensor<4x8xf32>, replicated, axis = -1, offset = [0, 0], tile = [4, 8]>) -> !dist.distribution<tensor<4x8xf32>, replicated, axis = -1>
    return
  }

  // CHECK-LABEL: func.func @sharded_single_shard_covers
  func.func @sharded_single_shard_covers() {
    %g = dist.global : !dist.global<tensor<4xf32>>
    %s0 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<4xf32>, sharded, axis = 0, offset = [0], tile = [4]>
    %d = dist.distribution %g shards(%s0) : (!dist.global<tensor<4xf32>>, !dist.shard<tensor<4xf32>, sharded, axis = 0, offset = [0], tile = [4]>) -> !dist.distribution<tensor<4xf32>, sharded, axis = 0>
    return
  }

  // CHECK-LABEL: func.func @three_shards_cover
  func.func @three_shards_cover() {
    %g = dist.global : !dist.global<tensor<4xf32>>
    %s0 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>
    %s1 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [1], tile = [2]>
    %s2 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [3], tile = [1]>
    %d = dist.distribution %g shards(%s0, %s1, %s2) : (!dist.global<tensor<4xf32>>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>, !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [1], tile = [2]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [3], tile = [1]>) -> !dist.distribution<tensor<4xf32>, sharded, axis = 0>
    return
  }
}
