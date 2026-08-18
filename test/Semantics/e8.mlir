// RUN: s2c2-opt %s --check-s2c2-execution -verify-diagnostics

// E8: StageOrder is directed. Read in S1 is not HB-after write in S2.
func.func @e8_pipeline_reverse_undefined(%t: tensor<4xf32>) {
  %w = stor.object : !stor.object<tensor<4xf32>>
  %hbm = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
  sched.pipeline {
    sched.stage "read" {
      // expected-error@+1 {{read of residency is undefined}}
      %v = stor.unpack %hbm : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
      sched.yield
    }
    sched.stage "write" {
      stor.pack %t into %hbm : tensor<4xf32>, !stor.buffer<tensor<4xf32>, hbm>
      sched.yield
    }
    sched.yield
  }
  return
}
