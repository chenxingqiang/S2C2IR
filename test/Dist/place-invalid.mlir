// RUN: s2c2-opt %s -split-input-file -verify-diagnostics

// Placement legality is separate from shard coverage. A coordinate has to
// sit on the mesh, the rank has to be that coordinate, the topology has to
// be that mesh, and each coordinate is used once. Two HBM residencies are
// not two devices.

func.func @device_coord_outside_mesh() {
  %mesh = dist.mesh : !dist.mesh<[2, 2], ["row", "col"]>
  // expected-error@+1 {{device coordinate is outside the mesh}}
  %dev = dist.device %mesh : !dist.mesh<[2, 2], ["row", "col"]> -> !dist.device<[2, 2], ["row", "col"], [2, 0], rank = 2>
  return
}

// -----

func.func @rank_does_not_match_coord() {
  %mesh = dist.mesh : !dist.mesh<[2, 2], ["row", "col"]>
  // expected-error@+1 {{device rank does not match its mesh coordinate}}
  %dev = dist.device %mesh : !dist.mesh<[2, 2], ["row", "col"]> -> !dist.device<[2, 2], ["row", "col"], [0, 1], rank = 0>
  return
}

// -----

func.func @topology_does_not_match_mesh() {
  %g = dist.global : !dist.global<tensor<4xf32>>
  %s0 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>
  %s1 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [1], tile = [1]>
  %s2 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [2], tile = [1]>
  %s3 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [3], tile = [1]>
  %d = dist.distribution %g shards(%s0, %s1, %s2, %s3) : (!dist.global<tensor<4xf32>>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [1], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [2], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [3], tile = [1]>) -> !dist.distribution<tensor<4xf32>, sharded, axis = 0>
  %mesh = dist.mesh : !dist.mesh<[2, 2], ["row", "col"]>
  %g00 = dist.device %mesh : !dist.mesh<[2, 2], ["row", "col"]> -> !dist.device<[2, 2], ["row", "col"], [0, 0], rank = 0>
  %g01 = dist.device %mesh : !dist.mesh<[2, 2], ["row", "col"]> -> !dist.device<[2, 2], ["row", "col"], [0, 1], rank = 1>
  %g10 = dist.device %mesh : !dist.mesh<[2, 2], ["row", "col"]> -> !dist.device<[2, 2], ["row", "col"], [1, 0], rank = 2>
  %g11 = dist.device %mesh : !dist.mesh<[2, 2], ["row", "col"]> -> !dist.device<[2, 2], ["row", "col"], [1, 1], rank = 3>
  %line = dist.topology : !dist.topology<line, [4]>
  // expected-error@+1 {{topology does not match the device mesh}}
  %map = dist.place %d, %line, %mesh devices(%g00, %g01, %g10, %g11) shards(%s0, %s1, %s2, %s3) : (!dist.distribution<tensor<4xf32>, sharded, axis = 0>, !dist.topology<line, [4]>, !dist.mesh<[2, 2], ["row", "col"]>, !dist.device<[2, 2], ["row", "col"], [0, 0], rank = 0>, !dist.device<[2, 2], ["row", "col"], [0, 1], rank = 1>, !dist.device<[2, 2], ["row", "col"], [1, 0], rank = 2>, !dist.device<[2, 2], ["row", "col"], [1, 1], rank = 3>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [1], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [2], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [3], tile = [1]>) -> !dist.mapping<line, [4]>
  return
}

// -----

func.func @two_shards_one_coordinate() {
  %g = dist.global : !dist.global<tensor<2xf32>>
  %s0 = dist.shard %g : !dist.global<tensor<2xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>
  %s1 = dist.shard %g : !dist.global<tensor<2xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [1], tile = [1]>
  %d = dist.distribution %g shards(%s0, %s1) : (!dist.global<tensor<2xf32>>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [1], tile = [1]>) -> !dist.distribution<tensor<2xf32>, sharded, axis = 0>
  %mesh = dist.mesh : !dist.mesh<[2], ["node"]>
  %a = dist.device %mesh : !dist.mesh<[2], ["node"]> -> !dist.device<[2], ["node"], [0], rank = 0>
  %b = dist.device %mesh : !dist.mesh<[2], ["node"]> -> !dist.device<[2], ["node"], [0], rank = 0>
  %topo = dist.topology : !dist.topology<line, [2]>
  // expected-error@+1 {{placement maps two shards to one device coordinate}}
  %map = dist.place %d, %topo, %mesh devices(%a, %b) shards(%s0, %s1) : (!dist.distribution<tensor<2xf32>, sharded, axis = 0>, !dist.topology<line, [2]>, !dist.mesh<[2], ["node"]>, !dist.device<[2], ["node"], [0], rank = 0>, !dist.device<[2], ["node"], [0], rank = 0>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [1], tile = [1]>) -> !dist.mapping<line, [2]>
  return
}

// -----

func.func @hbm_buffers_are_not_devices() {
  %w = stor.object : !stor.object<tensor<2xf32>>
  %a = stor.materialize %w : !stor.object<tensor<2xf32>> -> !stor.buffer<tensor<2xf32>, hbm>
  %b = stor.materialize %w : !stor.object<tensor<2xf32>> -> !stor.buffer<tensor<2xf32>, hbm>
  %g = dist.global : !dist.global<tensor<2xf32>>
  %s0 = dist.shard %g : !dist.global<tensor<2xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>
  %s1 = dist.shard %g : !dist.global<tensor<2xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [1], tile = [1]>
  %d = dist.distribution %g shards(%s0, %s1) : (!dist.global<tensor<2xf32>>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [1], tile = [1]>) -> !dist.distribution<tensor<2xf32>, sharded, axis = 0>
  %mesh = dist.mesh : !dist.mesh<[2], ["node"]>
  %topo = dist.topology : !dist.topology<line, [2]>
  // expected-error@+1 {{storage residency is not a device; a device has mesh coordinates}}
  %map = dist.place %d, %topo, %mesh devices(%a, %b) shards(%s0, %s1) : (!dist.distribution<tensor<2xf32>, sharded, axis = 0>, !dist.topology<line, [2]>, !dist.mesh<[2], ["node"]>, !stor.buffer<tensor<2xf32>, hbm>, !stor.buffer<tensor<2xf32>, hbm>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [1], tile = [1]>) -> !dist.mapping<line, [2]>
  return
}

// -----

func.func @device_from_another_mesh() {
  %g = dist.global : !dist.global<tensor<2xf32>>
  %s0 = dist.shard %g : !dist.global<tensor<2xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>
  %s1 = dist.shard %g : !dist.global<tensor<2xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [1], tile = [1]>
  %d = dist.distribution %g shards(%s0, %s1) : (!dist.global<tensor<2xf32>>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [1], tile = [1]>) -> !dist.distribution<tensor<2xf32>, sharded, axis = 0>
  %here = dist.mesh : !dist.mesh<[2], ["node"]>
  %other = dist.mesh : !dist.mesh<[2], ["node"]>
  %a = dist.device %other : !dist.mesh<[2], ["node"]> -> !dist.device<[2], ["node"], [0], rank = 0>
  %b = dist.device %other : !dist.mesh<[2], ["node"]> -> !dist.device<[2], ["node"], [1], rank = 1>
  %topo = dist.topology : !dist.topology<line, [2]>
  // expected-error@+1 {{device is not on this mesh}}
  %map = dist.place %d, %topo, %here devices(%a, %b) shards(%s0, %s1) : (!dist.distribution<tensor<2xf32>, sharded, axis = 0>, !dist.topology<line, [2]>, !dist.mesh<[2], ["node"]>, !dist.device<[2], ["node"], [0], rank = 0>, !dist.device<[2], ["node"], [1], rank = 1>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [1], tile = [1]>) -> !dist.mapping<line, [2]>
  return
}

// -----

func.func @rank_does_not_fit_in_int64() {
  %mesh = dist.mesh : !dist.mesh<[3, 4611686018427387904], ["row", "col"]>
  // expected-error@+1 {{device rank does not match its mesh coordinate}}
  %dev = dist.device %mesh : !dist.mesh<[3, 4611686018427387904], ["row", "col"]> -> !dist.device<[3, 4611686018427387904], ["row", "col"], [2, 0], rank = 0>
  return
}

// -----

func.func @placement_drops_a_shard() {
  %g = dist.global : !dist.global<tensor<2xf32>>
  %s0 = dist.shard %g : !dist.global<tensor<2xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>
  %s1 = dist.shard %g : !dist.global<tensor<2xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [1], tile = [1]>
  %d = dist.distribution %g shards(%s0, %s1) : (!dist.global<tensor<2xf32>>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [1], tile = [1]>) -> !dist.distribution<tensor<2xf32>, sharded, axis = 0>
  %mesh = dist.mesh : !dist.mesh<[2], ["node"]>
  %a = dist.device %mesh : !dist.mesh<[2], ["node"]> -> !dist.device<[2], ["node"], [0], rank = 0>
  %topo = dist.topology : !dist.topology<line, [2]>
  // expected-error@+1 {{placement must name each shard of the distribution once}}
  %map = dist.place %d, %topo, %mesh devices(%a) shards(%s0) : (!dist.distribution<tensor<2xf32>, sharded, axis = 0>, !dist.topology<line, [2]>, !dist.mesh<[2], ["node"]>, !dist.device<[2], ["node"], [0], rank = 0>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>) -> !dist.mapping<line, [2]>
  return
}
