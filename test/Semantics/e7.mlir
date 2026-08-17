// RUN: s2c2-opt %s --check-s2c2-execution -verify-diagnostics

// E7: T1 listed before T2 is not HB. Lexical sibling order ∉ HB.
func.func @e7_lexical_order_is_not_hb(%t: tensor<4xf32>) {
  %w = stor.object : !stor.object<tensor<4xf32>>
  %ssd = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, ssd>
  %hbm = stor.materialize %w : !stor.object<tensor<4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
  stor.pack %t into %ssd : tensor<4xf32>, !stor.buffer<tensor<4xf32>, ssd>
  sched.concurrent {
    %t1 = sched.task {
      %e = comm.stream %ssd, %hbm : !stor.buffer<tensor<4xf32>, ssd>, !stor.buffer<tensor<4xf32>, hbm> -> !sched.token
      sched.yield
    }
    %t2 = sched.task {
      // expected-error@+1 {{read of residency is undefined}}
      %v = stor.unpack %hbm : !stor.buffer<tensor<4xf32>, hbm> -> tensor<4xf32>
      sched.yield
    }
    sched.yield
  }
  return
}
