// RUN: s2c2-opt %s --check-s2c2-execution -verify-diagnostics

// E1: materialize is not a fill. Unpack without a prior write is undefined.
func.func @e1_materialize_then_unpack() {
  %w = stor.object : !stor.object<tensor<4xf32>>
  %hbm = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
  // expected-error@+1 {{read of residency is undefined}}
  %v = stor.unpack %hbm : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
  return
}
