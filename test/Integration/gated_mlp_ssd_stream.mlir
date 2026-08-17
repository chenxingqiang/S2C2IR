// RUN: s2c2-opt %s | s2c2-opt | FileCheck %s

// SSD-streaming Gated MLP with compute/communication overlap.
// Weights start on SSD, are streamed into HBM, and compute overlaps the
// next prefetch.

module {
  // CHECK-LABEL: func.func @gated_mlp_ssd_stream
  func.func @gated_mlp_ssd_stream(%x: tensor<1x4096xf16>) -> tensor<1x4096xf16> {
    // CHECK: stor.alloc : !stor.buffer<tensor<4096x11008xf16>, ssd>
    %w_gate_ssd = stor.alloc : !stor.buffer<tensor<4096x11008xf16>, ssd>
    %w_up_ssd = stor.alloc : !stor.buffer<tensor<4096x11008xf16>, ssd>
    %w_down_ssd = stor.alloc : !stor.buffer<tensor<11008x4096xf16>, ssd>

    // CHECK: stor.alloc : !stor.buffer<tensor<4096x11008xf16>, hbm>
    %w_gate_hbm = stor.alloc : !stor.buffer<tensor<4096x11008xf16>, hbm>
    %w_up_hbm = stor.alloc : !stor.buffer<tensor<4096x11008xf16>, hbm>
    %w_down_hbm = stor.alloc : !stor.buffer<tensor<11008x4096xf16>, hbm>

    // CHECK: comm.stream {{.*}} -> !sched.token
    %t_gate = comm.stream %w_gate_ssd, %w_gate_hbm {engine = #comm.engine<dma>}
      : !stor.buffer<tensor<4096x11008xf16>, ssd>, !stor.buffer<tensor<4096x11008xf16>, hbm> -> !sched.token
    %t_up = comm.stream %w_up_ssd, %w_up_hbm {engine = #comm.engine<dma>}
      : !stor.buffer<tensor<4096x11008xf16>, ssd>, !stor.buffer<tensor<4096x11008xf16>, hbm> -> !sched.token

    // CHECK: sched.overlap -> tensor<1x4096xf16>
    // CHECK: sched.wait
    // CHECK: stor.unpack
    // CHECK: comp.gated_mlp
    // CHECK: comm.stream
    %y = sched.overlap -> tensor<1x4096xf16> {
      sched.wait %t_gate, %t_up : !sched.token, !sched.token
      %wg = stor.unpack %w_gate_hbm : !stor.buffer<tensor<4096x11008xf16>, hbm> -> tensor<4096x11008xf16>
      %wu = stor.unpack %w_up_hbm : !stor.buffer<tensor<4096x11008xf16>, hbm> -> tensor<4096x11008xf16>
      %wd = stor.unpack %w_down_hbm : !stor.buffer<tensor<11008x4096xf16>, hbm> -> tensor<11008x4096xf16>
      %out = comp.gated_mlp %x, %wg, %wu, %wd {activation = #comp.activation<silu>, unit = #comp.unit<npu>}
        : tensor<1x4096xf16>, tensor<4096x11008xf16>, tensor<4096x11008xf16>, tensor<11008x4096xf16>
          -> tensor<1x4096xf16>
      sched.yield %out : tensor<1x4096xf16>
    } {
      %t_down = comm.stream %w_down_ssd, %w_down_hbm {engine = #comm.engine<dma>}
        : !stor.buffer<tensor<11008x4096xf16>, ssd>, !stor.buffer<tensor<11008x4096xf16>, hbm> -> !sched.token
      sched.yield
    }

    stor.dealloc %w_gate_ssd : !stor.buffer<tensor<4096x11008xf16>, ssd>
    stor.dealloc %w_up_ssd : !stor.buffer<tensor<4096x11008xf16>, ssd>
    stor.dealloc %w_down_ssd : !stor.buffer<tensor<11008x4096xf16>, ssd>
    stor.dealloc %w_gate_hbm : !stor.buffer<tensor<4096x11008xf16>, hbm>
    stor.dealloc %w_up_hbm : !stor.buffer<tensor<4096x11008xf16>, hbm>
    stor.dealloc %w_down_hbm : !stor.buffer<tensor<11008x4096xf16>, hbm>
    return %y : tensor<1x4096xf16>
  }
}
