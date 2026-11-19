// RUN: s2c2-opt %s | s2c2-opt | FileCheck %s

// One logical distribution, two hardware topologies. Shard offsets, tiles,
// and the compute op stay the same. The grid and the line are different
// meshes: coordinates live on the device type.

module {
  // CHECK-LABEL: func.func @same_shards_two_topologies
  func.func @same_shards_two_topologies(%v : tensor<1xf32>) -> tensor<1xf32> {
    // CHECK: %[[G:.*]] = dist.global : !dist.global<tensor<4xf32>>
    %g = dist.global : !dist.global<tensor<4xf32>>
    // CHECK: %[[S0:.*]] = dist.shard %[[G]] : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>
    %s0 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>
    // CHECK: %[[S1:.*]] = dist.shard %[[G]] : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [1], tile = [1]>
    %s1 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [1], tile = [1]>
    // CHECK: %[[S2:.*]] = dist.shard %[[G]] : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [2], tile = [1]>
    %s2 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [2], tile = [1]>
    // CHECK: %[[S3:.*]] = dist.shard %[[G]] : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [3], tile = [1]>
    %s3 = dist.shard %g : !dist.global<tensor<4xf32>> -> !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [3], tile = [1]>
    // CHECK: %[[D:.*]] = dist.distribution %[[G]] shards(%[[S0]], %[[S1]], %[[S2]], %[[S3]]) : (!dist.global<tensor<4xf32>>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [1], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [2], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [3], tile = [1]>) -> !dist.distribution<tensor<4xf32>, sharded, axis = 0>
    %d = dist.distribution %g shards(%s0, %s1, %s2, %s3) : (!dist.global<tensor<4xf32>>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [1], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [2], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [3], tile = [1]>) -> !dist.distribution<tensor<4xf32>, sharded, axis = 0>

    // CHECK: %[[Y:.*]] = comp.elemwise %[[V:.*]] {kind = #comp.elemwise<silu>} : tensor<1xf32> -> tensor<1xf32>
    %y = comp.elemwise %v {kind = #comp.elemwise<silu>} : tensor<1xf32> -> tensor<1xf32>

    // CHECK: %[[GRID:.*]] = dist.mesh : !dist.mesh<[2, 2], ["row", "col"]>
    %grid = dist.mesh : !dist.mesh<[2, 2], ["row", "col"]>
    // CHECK: %[[G00:.*]] = dist.device %[[GRID]] : !dist.mesh<[2, 2], ["row", "col"]> -> !dist.device<[2, 2], ["row", "col"], [0, 0], rank = 0>
    %g00 = dist.device %grid : !dist.mesh<[2, 2], ["row", "col"]> -> !dist.device<[2, 2], ["row", "col"], [0, 0], rank = 0>
    // CHECK: %[[G01:.*]] = dist.device %[[GRID]] : !dist.mesh<[2, 2], ["row", "col"]> -> !dist.device<[2, 2], ["row", "col"], [0, 1], rank = 1>
    %g01 = dist.device %grid : !dist.mesh<[2, 2], ["row", "col"]> -> !dist.device<[2, 2], ["row", "col"], [0, 1], rank = 1>
    // CHECK: %[[G10:.*]] = dist.device %[[GRID]] : !dist.mesh<[2, 2], ["row", "col"]> -> !dist.device<[2, 2], ["row", "col"], [1, 0], rank = 2>
    %g10 = dist.device %grid : !dist.mesh<[2, 2], ["row", "col"]> -> !dist.device<[2, 2], ["row", "col"], [1, 0], rank = 2>
    // CHECK: %[[G11:.*]] = dist.device %[[GRID]] : !dist.mesh<[2, 2], ["row", "col"]> -> !dist.device<[2, 2], ["row", "col"], [1, 1], rank = 3>
    %g11 = dist.device %grid : !dist.mesh<[2, 2], ["row", "col"]> -> !dist.device<[2, 2], ["row", "col"], [1, 1], rank = 3>
    // CHECK: %[[GTOPO:.*]] = dist.topology : !dist.topology<grid, [2, 2]>
    %gtopo = dist.topology : !dist.topology<grid, [2, 2]>
    // CHECK: dist.place %[[D]], %[[GTOPO]], %[[GRID]] devices(%[[G00]], %[[G01]], %[[G10]], %[[G11]]) shards(%[[S0]], %[[S1]], %[[S2]], %[[S3]]) : (!dist.distribution<tensor<4xf32>, sharded, axis = 0>, !dist.topology<grid, [2, 2]>, !dist.mesh<[2, 2], ["row", "col"]>, !dist.device<[2, 2], ["row", "col"], [0, 0], rank = 0>, !dist.device<[2, 2], ["row", "col"], [0, 1], rank = 1>, !dist.device<[2, 2], ["row", "col"], [1, 0], rank = 2>, !dist.device<[2, 2], ["row", "col"], [1, 1], rank = 3>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [1], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [2], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [3], tile = [1]>) -> !dist.mapping<grid, [2, 2]>
    %gmap = dist.place %d, %gtopo, %grid devices(%g00, %g01, %g10, %g11) shards(%s0, %s1, %s2, %s3) : (!dist.distribution<tensor<4xf32>, sharded, axis = 0>, !dist.topology<grid, [2, 2]>, !dist.mesh<[2, 2], ["row", "col"]>, !dist.device<[2, 2], ["row", "col"], [0, 0], rank = 0>, !dist.device<[2, 2], ["row", "col"], [0, 1], rank = 1>, !dist.device<[2, 2], ["row", "col"], [1, 0], rank = 2>, !dist.device<[2, 2], ["row", "col"], [1, 1], rank = 3>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [1], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [2], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [3], tile = [1]>) -> !dist.mapping<grid, [2, 2]>

    // CHECK: %[[LINE:.*]] = dist.mesh : !dist.mesh<[4], ["node"]>
    %line = dist.mesh : !dist.mesh<[4], ["node"]>
    // CHECK: %[[N0:.*]] = dist.device %[[LINE]] : !dist.mesh<[4], ["node"]> -> !dist.device<[4], ["node"], [0], rank = 0>
    %n0 = dist.device %line : !dist.mesh<[4], ["node"]> -> !dist.device<[4], ["node"], [0], rank = 0>
    // CHECK: %[[N1:.*]] = dist.device %[[LINE]] : !dist.mesh<[4], ["node"]> -> !dist.device<[4], ["node"], [1], rank = 1>
    %n1 = dist.device %line : !dist.mesh<[4], ["node"]> -> !dist.device<[4], ["node"], [1], rank = 1>
    // CHECK: %[[N2:.*]] = dist.device %[[LINE]] : !dist.mesh<[4], ["node"]> -> !dist.device<[4], ["node"], [2], rank = 2>
    %n2 = dist.device %line : !dist.mesh<[4], ["node"]> -> !dist.device<[4], ["node"], [2], rank = 2>
    // CHECK: %[[N3:.*]] = dist.device %[[LINE]] : !dist.mesh<[4], ["node"]> -> !dist.device<[4], ["node"], [3], rank = 3>
    %n3 = dist.device %line : !dist.mesh<[4], ["node"]> -> !dist.device<[4], ["node"], [3], rank = 3>
    // CHECK: %[[LTOPO:.*]] = dist.topology : !dist.topology<line, [4]>
    %ltopo = dist.topology : !dist.topology<line, [4]>
    // CHECK: dist.place %[[D]], %[[LTOPO]], %[[LINE]] devices(%[[N0]], %[[N1]], %[[N2]], %[[N3]]) shards(%[[S0]], %[[S1]], %[[S2]], %[[S3]]) : (!dist.distribution<tensor<4xf32>, sharded, axis = 0>, !dist.topology<line, [4]>, !dist.mesh<[4], ["node"]>, !dist.device<[4], ["node"], [0], rank = 0>, !dist.device<[4], ["node"], [1], rank = 1>, !dist.device<[4], ["node"], [2], rank = 2>, !dist.device<[4], ["node"], [3], rank = 3>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [1], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [2], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [3], tile = [1]>) -> !dist.mapping<line, [4]>
    %lmap = dist.place %d, %ltopo, %line devices(%n0, %n1, %n2, %n3) shards(%s0, %s1, %s2, %s3) : (!dist.distribution<tensor<4xf32>, sharded, axis = 0>, !dist.topology<line, [4]>, !dist.mesh<[4], ["node"]>, !dist.device<[4], ["node"], [0], rank = 0>, !dist.device<[4], ["node"], [1], rank = 1>, !dist.device<[4], ["node"], [2], rank = 2>, !dist.device<[4], ["node"], [3], rank = 3>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [0], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [1], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [2], tile = [1]>, !dist.shard<tensor<1xf32>, sharded, axis = 0, offset = [3], tile = [1]>) -> !dist.mapping<line, [4]>
    return %y : tensor<1xf32>
  }

  // 3 * 2^62 does not fit in int64. The origin and the device one step
  // along the slow axis still have representable ranks.
  // CHECK-LABEL: func.func @rank_fits_when_mesh_product_overflows
  func.func @rank_fits_when_mesh_product_overflows() {
    // CHECK: %[[M:.*]] = dist.mesh : !dist.mesh<[3, 4611686018427387904], ["row", "col"]>
    %m = dist.mesh : !dist.mesh<[3, 4611686018427387904], ["row", "col"]>
    // CHECK: dist.device %[[M]] : !dist.mesh<[3, 4611686018427387904], ["row", "col"]> -> !dist.device<[3, 4611686018427387904], ["row", "col"], [0, 0], rank = 0>
    %origin = dist.device %m : !dist.mesh<[3, 4611686018427387904], ["row", "col"]> -> !dist.device<[3, 4611686018427387904], ["row", "col"], [0, 0], rank = 0>
    // CHECK: dist.device %[[M]] : !dist.mesh<[3, 4611686018427387904], ["row", "col"]> -> !dist.device<[3, 4611686018427387904], ["row", "col"], [0, 1], rank = 1>
    %fast = dist.device %m : !dist.mesh<[3, 4611686018427387904], ["row", "col"]> -> !dist.device<[3, 4611686018427387904], ["row", "col"], [0, 1], rank = 1>
    // CHECK: dist.device %[[M]] : !dist.mesh<[3, 4611686018427387904], ["row", "col"]> -> !dist.device<[3, 4611686018427387904], ["row", "col"], [1, 0], rank = 4611686018427387904>
    %slow = dist.device %m : !dist.mesh<[3, 4611686018427387904], ["row", "col"]> -> !dist.device<[3, 4611686018427387904], ["row", "col"], [1, 0], rank = 4611686018427387904>
    return
  }
}
