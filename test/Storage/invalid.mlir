// RUN: s2c2-opt %s -split-input-file -verify-diagnostics

func.func @unpack_mismatch() {
  %buf = stor.alloc : !stor.buffer<tensor<2x4xf32>, hbm>
  // expected-error@+1 {{unpacked tensor type must match buffer payload}}
  %t = stor.unpack %buf : !stor.buffer<tensor<2x4xf32>, hbm> -> tensor<4xf32>
  return
}
