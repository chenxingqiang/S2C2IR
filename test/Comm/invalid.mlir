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

// -----

func.func @stream_different_objects() {
  %a = stor.object : !stor.object<tensor<2xf32>>
  %b = stor.object : !stor.object<tensor<2xf32>>
  %src = stor.materialize %a : !stor.object<tensor<2xf32>> -> !stor.buffer<tensor<2xf32>, ssd>
  %dst = stor.materialize %b : !stor.object<tensor<2xf32>> -> !stor.buffer<tensor<2xf32>, hbm>
  // expected-error@+1 {{source and destination must be residencies of the same logical object}}
  %t = comm.stream %src, %dst : !stor.buffer<tensor<2xf32>, ssd>, !stor.buffer<tensor<2xf32>, hbm> -> !sched.token
  return
}

// -----

func.func @stream_mix_anonymous() {
  %w = stor.object : !stor.object<tensor<2xf32>>
  %src = stor.alloc : !stor.buffer<tensor<2xf32>, ssd>
  %dst = stor.materialize %w : !stor.object<tensor<2xf32>> -> !stor.buffer<tensor<2xf32>, hbm>
  // expected-error@+1 {{cannot mix object-backed and anonymous buffers}}
  %t = comm.stream %src, %dst : !stor.buffer<tensor<2xf32>, ssd>, !stor.buffer<tensor<2xf32>, hbm> -> !sched.token
  return
}
