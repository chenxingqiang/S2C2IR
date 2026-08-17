// RUN: s2c2-opt %s -split-input-file -verify-diagnostics

func.func @stream_payload_mismatch() {
  %src = stor.alloc : !stor.buffer<tensor<2xf32>, ssd>
  %dst = stor.alloc : !stor.buffer<tensor<4xf32>, hbm>
  // expected-error@+1 {{source and destination buffer payload types must match}}
  %t = comm.stream %src, %dst : !stor.buffer<tensor<2xf32>, ssd>, !stor.buffer<tensor<4xf32>, hbm> -> !sched.token
  return
}

// -----

func.func @stream_same_space() {
  %src = stor.alloc : !stor.buffer<tensor<2xf32>, hbm>
  %dst = stor.alloc : !stor.buffer<tensor<2xf32>, hbm>
  // expected-error@+1 {{source and destination storage spaces must differ}}
  %t = comm.stream %src, %dst : !stor.buffer<tensor<2xf32>, hbm>, !stor.buffer<tensor<2xf32>, hbm> -> !sched.token
  return
}
