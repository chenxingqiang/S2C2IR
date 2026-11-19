// RUN: s2c2-opt %s --check-s2c2-distribution 2>&1 | FileCheck %s

// Two HBM materializations of one object are two residencies. A shard.grid
// in the same module does not turn those buffers into mesh ranks.
// The checker prints before the module, so both lines are unordered.

// CHECK-DAG: func.func @two_hbm_materialize_are_not_devices
// CHECK-DAG: distribution @two_hbm_materialize_are_not_devices hbm-replicas=2 mesh-size=2 residencies-are-devices=no

module {
  shard.grid @devices(shape = 2)

  func.func @two_hbm_materialize_are_not_devices() {
    %w = stor.object : !stor.object<tensor<4xf32>>
    %a = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    %b = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
    return
  }
}
