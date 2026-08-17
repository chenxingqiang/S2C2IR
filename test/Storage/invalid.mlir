// RUN: s2c2-opt %s -split-input-file -verify-diagnostics

func.func @unpack_mismatch() {
  %buf = stor.alloc : !stor.buffer<tensor<2x4xf32>, hbm>
  // expected-error@+1 {{unpacked tensor type must match buffer payload}}
  %t = stor.unpack %buf : !stor.buffer<tensor<2x4xf32>, hbm> -> tensor<4xf32>
  return
}

// -----

func.func @materialize_mismatch() {
  %w = stor.object : !stor.object<tensor<2x4xf32>>
  // expected-error@+1 {{materialized buffer payload must match logical object}}
  %buf = stor.materialize %w : !stor.object<tensor<2x4xf32>> -> !stor.buffer<tensor<4xf32>, hbm>
  return
}

// -----

func.func @transfer_mismatch() {
  %w = stor.object : !stor.object<tensor<2x4xf32>>
  %ssd = stor.materialize %w : !stor.object<tensor<2x4xf32>> -> !stor.buffer<tensor<2x4xf32>, ssd>
  // expected-error@+1 {{transfer result payload must match the source buffer payload}}
  %hbm = stor.transfer %ssd : !stor.buffer<tensor<2x4xf32>, ssd> -> !stor.buffer<tensor<4xf32>, hbm>
  return
}
