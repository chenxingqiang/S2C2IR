// RUN: s2c2-opt %s -split-input-file -verify-diagnostics

// Sharded ranges are half-open [offset, offset + tile) on the partition
// axis. The distribution verifier reports out of bounds, then overlap,
// then a gap. A partial replicated tile is not a shard of the whole tensor.

func.func @shard_exceeds_global() {
  %g = dist.global : !dist.global<tensor<4xf32>>
  // expected-error@+1 {{shard range exceeds the global tensor}}
  %s = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<3xf32>, sharded, axis = 0, offset = [2], tile = [3]>
  return
}

// -----

func.func @shards_overlap() {
  %g = dist.global : !dist.global<tensor<4xf32>>
  %s0 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<3xf32>, sharded, axis = 0, offset = [0], tile = [3]>
  %s1 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [2], tile = [2]>
  // expected-error@+1 {{shards overlap}}
  %d = dist.distribution %g shards(%s0, %s1) : (!dist.global<tensor<4xf32>>, !dist.shard<tensor<3xf32>, sharded, axis = 0, offset = [0], tile = [3]>, !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [2], tile = [2]>) -> !dist.distribution<tensor<4xf32>, sharded, axis = 0>
  return
}

// -----

func.func @shards_leave_a_gap() {
  %g = dist.global : !dist.global<tensor<4xf32>>
  %s0 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [0], tile = [2]>
  %s1 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [3], tile = [1]>
  // expected-error@+1 {{shards do not cover the global tensor}}
  %d = dist.distribution %g shards(%s0, %s1) : (!dist.global<tensor<4xf32>>, !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [0], tile = [2]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [3], tile = [1]>) -> !dist.distribution<tensor<4xf32>, sharded, axis = 0>
  return
}

// -----

func.func @shards_overlap_and_gap() {
  %g = dist.global : !dist.global<tensor<4xf32>>
  %s0 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<3xf32>, sharded, axis = 0, offset = [0], tile = [3]>
  %s1 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [2], tile = [1]>
  // expected-error@+1 {{shards overlap}}
  %d = dist.distribution %g shards(%s0, %s1) : (!dist.global<tensor<4xf32>>, !dist.shard<tensor<3xf32>, sharded, axis = 0, offset = [0], tile = [3]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [2], tile = [1]>) -> !dist.distribution<tensor<4xf32>, sharded, axis = 0>
  return
}

// -----

func.func @replicated_is_not_a_partial_tile() {
  %g = dist.global : !dist.global<tensor<4xf32>>
  // expected-error@+1 {{replicated shard must cover the whole global tensor}}
  %s = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<2xf32>, replicated, axis = -1, offset = [0], tile = [2]>
  return
}

// -----

func.func @sharded_full_copies_overlap() {
  %g = dist.global : !dist.global<tensor<4xf32>>
  %s0 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<4xf32>, sharded, axis = 0, offset = [0], tile = [4]>
  %s1 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<4xf32>, sharded, axis = 0, offset = [0], tile = [4]>
  // expected-error@+1 {{shards overlap}}
  %d = dist.distribution %g shards(%s0, %s1) : (!dist.global<tensor<4xf32>>, !dist.shard<tensor<4xf32>, sharded, axis = 0, offset = [0], tile = [4]>, !dist.shard<tensor<4xf32>, sharded, axis = 0, offset = [0], tile = [4]>) -> !dist.distribution<tensor<4xf32>, sharded, axis = 0>
  return
}

// -----

func.func @sharded_off_axis_partial() {
  %g = dist.global : !dist.global<tensor<4x8xf32>>
  // expected-error@+1 {{sharded shard must be full-extent off the partition axis}}
  %s = dist.shard %g : !dist.global<tensor<4x8xf32>> -> !dist.shard<tensor<2x4xf32>, sharded, axis = 0, offset = [0, 0], tile = [2, 4]>
  return
}

// -----

func.func @shard_partition_axis_mismatch() {
  %g = dist.global : !dist.global<tensor<4x8xf32>>
  %s0 = dist.shard %g : !dist.global<tensor<4x8xf32>> -> !dist.shard<tensor<2x8xf32>, sharded, axis = 0, offset = [0, 0], tile = [2, 8]>
  %s1 = dist.shard %g : !dist.global<tensor<4x8xf32>> -> !dist.shard<tensor<2x8xf32>, sharded, axis = 0, offset = [2, 0], tile = [2, 8]>
  // expected-error@+1 {{shard partition axis must match the distribution}}
  %d = dist.distribution %g shards(%s0, %s1) : (!dist.global<tensor<4x8xf32>>, !dist.shard<tensor<2x8xf32>, sharded, axis = 0, offset = [0, 0], tile = [2, 8]>, !dist.shard<tensor<2x8xf32>, sharded, axis = 0, offset = [2, 0], tile = [2, 8]>) -> !dist.distribution<tensor<4x8xf32>, sharded, axis = 1>
  return
}

// -----

func.func @shard_placement_mismatch() {
  %g = dist.global : !dist.global<tensor<4xf32>>
  %s0 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [0], tile = [2]>
  %s1 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [2], tile = [2]>
  // expected-error@+1 {{shard placement must match the distribution}}
  %d = dist.distribution %g shards(%s0, %s1) : (!dist.global<tensor<4xf32>>, !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [0], tile = [2]>, !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [2], tile = [2]>) -> !dist.distribution<tensor<4xf32>, replicated, axis = -1>
  return
}

// -----

func.func @shard_not_part_of_this_global() {
  %g0 = dist.global : !dist.global<tensor<4xf32>>
  %g1 = dist.global : !dist.global<tensor<4xf32>>
  %s0 = dist.shard %g1 : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [0], tile = [2]>
  %s1 = dist.shard %g1 : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [2], tile = [2]>
  // expected-error@+1 {{shard is not part of this global tensor}}
  %d = dist.distribution %g0 shards(%s0, %s1) : (!dist.global<tensor<4xf32>>, !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [0], tile = [2]>, !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [2], tile = [2]>) -> !dist.distribution<tensor<4xf32>, sharded, axis = 0>
  return
}

// -----

func.func @local_tensor_mismatch() {
  %g = dist.global : !dist.global<tensor<4xf32>>
  %s0 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [0], tile = [2]>
  // expected-error@+1 {{local tensor must match the shard}}
  %l = dist.local %s0 : !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [0], tile = [2]> -> !dist.local<tensor<4xf32>>
  return
}

// -----

func.func @local_element_type_mismatch() {
  %g = dist.global : !dist.global<tensor<4xf32>>
  // expected-error@+1 {{local tensor element type must match the global tensor}}
  %s = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<2xf16>, sharded, axis = 0, offset = [0], tile = [2]>
  return
}

// -----

func.func @shard_rank_mismatch() {
  %g = dist.global : !dist.global<tensor<4xf32>>
  // expected-error@+1 {{shard offset and tile shape must have the global tensor rank}}
  %s = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<2x2xf32>, sharded, axis = 0, offset = [0, 0], tile = [2, 2]>
  return
}

// -----

func.func @shard_negative_offset() {
  %g = dist.global : !dist.global<tensor<4xf32>>
  // expected-error@+1 {{shard offset must be non-negative}}
  %s = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [-1], tile = [2]>
  return
}

// -----

func.func @shard_tile_mismatch() {
  %g = dist.global : !dist.global<tensor<4xf32>>
  // expected-error@+1 {{shard tile shape must match the local tensor}}
  %s = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [0], tile = [3]>
  return
}

// -----

func.func @shards_leave_a_gap_on_axis() {
  %g = dist.global : !dist.global<tensor<4x8xf32>>
  %s0 = dist.shard %g : !dist.global<tensor<4x8xf32>> -> !dist.shard<tensor<4x3xf32>, sharded, axis = 1, offset = [0, 0], tile = [4, 3]>
  %s1 = dist.shard %g : !dist.global<tensor<4x8xf32>> -> !dist.shard<tensor<4x4xf32>, sharded, axis = 1, offset = [0, 4], tile = [4, 4]>
  // expected-error@+1 {{shards do not cover the global tensor}}
  %d = dist.distribution %g shards(%s0, %s1) : (!dist.global<tensor<4x8xf32>>, !dist.shard<tensor<4x3xf32>, sharded, axis = 1, offset = [0, 0], tile = [4, 3]>, !dist.shard<tensor<4x4xf32>, sharded, axis = 1, offset = [0, 4], tile = [4, 4]>) -> !dist.distribution<tensor<4x8xf32>, sharded, axis = 1>
  return
}

// -----

func.func @distribution_requires_a_shard() {
  %g = dist.global : !dist.global<tensor<4xf32>>
  // expected-error@+1 {{distribution requires at least one shard}}
  %d = dist.distribution %g shards() : (!dist.global<tensor<4xf32>>) -> !dist.distribution<tensor<4xf32>, sharded, axis = 0>
  return
}

// -----

func.func @distribution_global_mismatch() {
  %g = dist.global : !dist.global<tensor<4xf32>>
  %s = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<4xf32>, replicated, axis = -1, offset = [0], tile = [4]>
  // expected-error@+1 {{distribution global tensor must match the global operand}}
  %d = dist.distribution %g shards(%s) : (!dist.global<tensor<4xf32>>, !dist.shard<tensor<4xf32>, replicated, axis = -1, offset = [0], tile = [4]>) -> !dist.distribution<tensor<8xf32>, replicated, axis = -1>
  return
}

// -----

func.func @same_shard_listed_twice() {
  %g = dist.global : !dist.global<tensor<4xf32>>
  %s0 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [0], tile = [2]>
  // expected-error@+1 {{shards overlap}}
  %d = dist.distribution %g shards(%s0, %s0) : (!dist.global<tensor<4xf32>>, !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [0], tile = [2]>, !dist.shard<tensor<2xf32>, sharded, axis = 0, offset = [0], tile = [2]>) -> !dist.distribution<tensor<4xf32>, sharded, axis = 0>
  return
}
