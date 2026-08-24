// RUN: s2c2-opt %s --s2c2-capability-query="device=rtx4090 producer=comp.silu consumer=comm.htod" 2>&1 | FileCheck %s --check-prefix=Q-HTOD
// RUN: s2c2-opt %s --s2c2-capability-query="device=rtx4090 producer=comp.silu consumer=comp.gemm" 2>&1 | FileCheck %s --check-prefix=Q-CC
// RUN: s2c2-opt %s --s2c2-capability-query="device=npu-demo producer=comp.silu consumer=comp.gemm" 2>&1 | FileCheck %s --check-prefix=Q-NPU
// RUN: s2c2-opt %s --s2c2-capability-query=device=rtx4090 2>&1 | FileCheck %s --check-prefix=WALK

// Capability query: catalog cells enter the compiler. No rewrite. Not Cost.
module {
  func.func @walk_pairs(%x: tensor<8xf32>, %w: tensor<8x8xf32>) {
    %obj = stor.object : !stor.object<tensor<8xf32>>
    %host = stor.materialize %obj : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, host>
    %hbm = stor.materialize %obj : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, hbm>
    stor.pack %x into %host : tensor<8xf32>, !stor.buffer<tensor<8xf32>, host>
    // WALK: "pair":"C||HtoD"
    // WALK-SAME: "pair_relation":"parallel"
    // WALK-SAME: "via":"concurrent"
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
    // WALK: "observed_constraint":"resource_contention"
    // WALK-SAME: "pair":"C_silu||C_gemm"
    // WALK-SAME: "pair_relation":"serial"
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

// Q-HTOD: capability-query
// Q-HTOD-SAME: "confidence":"measured"
// Q-HTOD-SAME: "observed_constraint":"none"
// Q-HTOD-SAME: "pair":"C||HtoD"
// Q-HTOD-SAME: "pair_relation":"parallel"
// Q-HTOD-SAME: "via":"catalog"

// Q-CC: capability-query
// Q-CC-SAME: "confidence":"arm_specific"
// Q-CC-SAME: "observed_constraint":"resource_contention"
// Q-CC-SAME: "pair":"C_silu||C_gemm"
// Q-CC-SAME: "pair_relation":"serial"

// Q-NPU: capability-query
// Q-NPU-SAME: "confidence":"inferred"
// Q-NPU-SAME: "observed_constraint":"none"
// Q-NPU-SAME: "pair":"C_silu||C_gemm"
// Q-NPU-SAME: "pair_relation":"parallel"
