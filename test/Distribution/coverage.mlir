// RUN: s2c2-opt %s --check-s2c2-distribution -split-input-file -verify-diagnostics 2>&1 | FileCheck %s

// Uniform split of axis 0. Global tensor<4x8xf32>, local tensor<2x8xf32>.
// The same tiles are a dist.distribution, so the checker reports a match.
// CHECK-DAG lines match the covered chunk. The gap chunk is
// -verify-diagnostics: a matched expected-error is not reprinted.

// CHECK-DAG: func.func @single_axis_cover
// CHECK-DAG: tensor<4x8xf32>
// CHECK-DAG: tensor<2x8xf32>
// CHECK-DAG: !stor.buffer<tensor<2x8xf32>, hbm>
// CHECK-DAG: distribution @single_axis_cover coverage=axis0:covered distribution-stor=match

module {
  shard.grid @tp(shape = 2)

  func.func @single_axis_cover() {
    %sharding = shard.sharding @tp split_axes = [[0]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4x8xf32>>
    %local0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<2x8xf32>>
    %local1 = stor.localize %global to %sharding rank = 1 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<2x8xf32>>
    %hbm = stor.materialize %local0 : !stor.object<tensor<2x8xf32>> -> !stor.buffer<tensor<2x8xf32>, hbm>
    %dg = dist.global : !dist.global<tensor<4x8xf32>>
    %s0 = dist.shard %dg : !dist.global<tensor<4x8xf32>> -> !dist.shard<tensor<2x8xf32>, sharded, axis = 0, offset = [0, 0], tile = [2, 8]>
    %s1 = dist.shard %dg : !dist.global<tensor<4x8xf32>> -> !dist.shard<tensor<2x8xf32>, sharded, axis = 0, offset = [2, 0], tile = [2, 8]>
    %d = dist.distribution %dg shards(%s0, %s1) : (!dist.global<tensor<4x8xf32>>, !dist.shard<tensor<2x8xf32>, sharded, axis = 0, offset = [0, 0], tile = [2, 8]>, !dist.shard<tensor<2x8xf32>, sharded, axis = 0, offset = [2, 0], tile = [2, 8]>) -> !dist.distribution<tensor<4x8xf32>, sharded, axis = 0>
    return
  }
}

// -----

// Prefix-sum offsets [0, 2, 3] fit, do not overlap, and leave [3, 4) uncovered.

module {
  shard.grid @tp(shape = 2)

  // expected-error@+1 {{shards do not cover the global tensor}}
  func.func @single_axis_gap() {
    %sharding = shard.sharding @tp split_axes = [[0]] sharded_dims_offsets = [0, 2, 3] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4x8xf32>>
    %local0 = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<2x8xf32>>
    %local1 = stor.localize %global to %sharding rank = 1 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<1x8xf32>>
    return
  }
}
