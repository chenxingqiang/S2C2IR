// RUN: s2c2-opt %s --s2c2-capability-query=device=rtx4090,producer=comp.silu,consumer=comm.htod 2>&1 | FileCheck %s --check-prefix=Q-HTOD
// RUN: s2c2-opt %s --s2c2-capability-query=device=rtx4090,producer=comp.silu,consumer=comp.gemm 2>&1 | FileCheck %s --check-prefix=Q-CC
// RUN: s2c2-opt %s --s2c2-capability-query=device=npu-demo,producer=comp.silu,consumer=comp.gemm 2>&1 | FileCheck %s --check-prefix=Q-NPU
// RUN: s2c2-opt %s --s2c2-capability-query=device=rtx4090 2>&1 | FileCheck %s --check-prefix=WALK

// Capability query: catalog cells enter the compiler. No rewrite. Not Cost.
module {
  func.func @walk_pairs(%x: tensor<8xf32>, %w: tensor<8x8xf32>) {
    %obj = stor.object : !stor.object<tensor<8xf32>>
    %host = stor.materialize %obj : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, host>
    %hbm = stor.materialize %obj : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, hbm>
    stor.pack %x into %host : tensor<8xf32>, !stor.buffer<tensor<8xf32>, host>
    // WALK: "pair":"C||HtoD"
    // WALK: "pair_relation":"parallel"
    // WALK: "via":"concurrent"
    sched.concurrent {
      %tc = sched.task {
        %v = stor.unpack %host : !stor.buffer<tensor<8xf32>, host> -> tensor<8xf32>
        %y = comp.elemwise %v {kind = #comp.elemwise<silu>} : tensor<8xf32> -> tensor<8xf32>
        sched.yield
      }
      %ts = sched.task {
        %e = comm.stream %host, %hbm : !stor.buffer<tensor<8xf32>, host>, !stor.buffer<tensor<8xf32>, hbm> -> !sched.token
        sched.yield
      }
      sched.yield
    }
    // WALK: "pair":"C_silu||C_gemm"
    // WALK: "pair_relation":"serial"
    // WALK: "observed_constraint":"resource_contention"
    sched.concurrent {
      %ta = sched.task {
        %y = comp.elemwise %x {kind = #comp.elemwise<silu>} : tensor<8xf32> -> tensor<8xf32>
        sched.yield
      }
      %tb = sched.task {
        %z = comp.matmul %x, %w : tensor<8xf32>, tensor<8x8xf32> -> tensor<8xf32>
        sched.yield
      }
      sched.yield
    }
    return
  }
}

// Q-HTOD: "pair":"C||HtoD"
// Q-HTOD: "pair_relation":"parallel"
// Q-HTOD: "observed_constraint":"none"
// Q-HTOD: "confidence":"measured"
// Q-HTOD: "via":"catalog"

// Q-CC: "pair":"C_silu||C_gemm"
// Q-CC: "pair_relation":"serial"
// Q-CC: "observed_constraint":"resource_contention"
// Q-CC: "confidence":"arm_specific"

// Q-NPU: "pair":"C_silu||C_gemm"
// Q-NPU: "pair_relation":"parallel"
// Q-NPU: "observed_constraint":"none"
// Q-NPU: "confidence":"inferred"
