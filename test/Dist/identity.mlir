// RUN: s2c2-opt %s --canonicalize | FileCheck %s

// Two globals of one type stay two tensors. Two identical replicas stay
// two shards. Canonicalization must not fold either pair.

// CHECK-LABEL: func.func @distinct_globals_and_replicas
func.func @distinct_globals_and_replicas() {
  // CHECK: %[[G0:.*]] = dist.global : !dist.global<tensor<4xf32>>
  // CHECK: %[[G1:.*]] = dist.global : !dist.global<tensor<4xf32>>
  %g0 = dist.global : !dist.global<tensor<4xf32>>
  %g1 = dist.global : !dist.global<tensor<4xf32>>
  // CHECK: %[[S0:.*]] = dist.shard %[[G0]] : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<4xf32>, replicated, axis = -1, offset = [0], tile = [4]>
  // CHECK: %[[S1:.*]] = dist.shard %[[G0]] : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<4xf32>, replicated, axis = -1, offset = [0], tile = [4]>
  %s0 = dist.shard %g0 : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<4xf32>, replicated, axis = -1, offset = [0], tile = [4]>
  %s1 = dist.shard %g0 : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<4xf32>, replicated, axis = -1, offset = [0], tile = [4]>
  // CHECK: dist.distribution %[[G0]] shards(%[[S0]], %[[S1]])
  %d = dist.distribution %g0 shards(%s0, %s1) : (!dist.global<tensor<4xf32>>, !dist.shard<tensor<4xf32>, replicated, axis = -1, offset = [0], tile = [4]>, !dist.shard<tensor<4xf32>, replicated, axis = -1, offset = [0], tile = [4]>) -> !dist.distribution<tensor<4xf32>, replicated, axis = -1>
  // CHECK: dist.shard %[[G1]]
  %s2 = dist.shard %g1 : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<4xf32>, replicated, axis = -1, offset = [0], tile = [4]>
  return
}
