// RUN: s2c2-opt %s --check-s2c2-distribution 2>&1 | FileCheck %s
// RUN: s2c2-opt %s --check-s2c2-execution

// MeshSize 1 is the existing single-device program: the local object has
// the global shape, and pack-then-unpack on that residency is still valid.

// CHECK-DAG: func.func @mesh_size_one_local_matches_global
// CHECK-DAG: distribution @mesh_size_one_local_matches_global coverage=replicated:covered mesh-size=1

module {
  shard.grid @solo(shape = 1)

  func.func @mesh_size_one_local_matches_global(%t: tensor<4x8xf32>) {
    %sharding = shard.sharding @solo split_axes = [[]] : !shard.sharding
    %global = stor.object : !stor.object<tensor<4x8xf32>>
    %local = stor.localize %global to %sharding rank = 0 : !stor.object<tensor<4x8xf32>>, !shard.sharding -> !stor.object<tensor<4x8xf32>>
    %hbm = stor.materialize %local : !stor.object<tensor<4x8xf32>> -> !stor.buffer<tensor<4x8xf32>, hbm>
    stor.pack %t into %hbm : tensor<4x8xf32>, !stor.buffer<tensor<4x8xf32>, hbm>
    %v = stor.unpack %hbm : !stor.buffer<tensor<4x8xf32>, hbm> -> tensor<4x8xf32>
    return
  }
}
