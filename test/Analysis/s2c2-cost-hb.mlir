// RUN: s2c2-opt %s --s2c2-cost-hb=device=cpu 2>&1 | FileCheck %s --check-prefix=CPU
// RUN: s2c2-opt %s --s2c2-cost-hb=device=gpu 2>&1 | FileCheck %s --check-prefix=GPU
// RUN: s2c2-opt %s --s2c2-cost=device=gpu 2>&1 | FileCheck %s --check-prefix=V01

// Cost Model v0.2: HB-aware overlap. Does not change --s2c2-cost (v0.1).
// Full score lines (not `overlap=0` substrings) so FileCheck cannot reuse H1.
module {
  // H1: Compute ∥ IO, no HB. GPU still gets credit (same as frozen K1).
  // CPU: s2c2-cost-hb device=cpu func=h1_concurrent compute=8 storage=64 communication=64 synchronization=0 overlap=0 total=136
  // GPU: s2c2-cost-hb device=gpu func=h1_concurrent compute=1 storage=64 communication=64 synchronization=0 overlap=1 total=128
  func.func @h1_concurrent(%t: tensor<8xf32>) {
    %obj = stor.object : !stor.object<tensor<8xf32>>
    %ssd = stor.materialize %obj : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, ssd>
    %hbm = stor.materialize %obj : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, hbm>
    stor.pack %t into %ssd : tensor<8xf32>, !stor.buffer<tensor<8xf32>, ssd>
    sched.concurrent {
      %tc = sched.task {
        %v = stor.unpack %ssd : !stor.buffer<tensor<8xf32>, ssd> -> tensor<8xf32>
        %y = comp.elemwise %v {kind = #comp.elemwise<silu>} : tensor<8xf32> -> tensor<8xf32>
        sched.yield
      }
      %ts = sched.task {
        %e = comm.stream %ssd, %hbm : !stor.buffer<tensor<8xf32>, ssd>, !stor.buffer<tensor<8xf32>, hbm> -> !sched.token
        sched.yield
      }
      sched.yield
    }
    return
  }

  // H2: no concurrent region.
  // CPU: s2c2-cost-hb device=cpu func=h2_sequential compute=8 storage=0 communication=0 synchronization=0 overlap=0 total=8
  // GPU: s2c2-cost-hb device=gpu func=h2_sequential compute=1 storage=0 communication=0 synchronization=0 overlap=0 total=1
  func.func @h2_sequential(%t: tensor<8xf32>) -> tensor<8xf32> {
    %y = comp.elemwise %t {kind = #comp.elemwise<silu>} : tensor<8xf32> -> tensor<8xf32>
    return %y : tensor<8xf32>
  }

  // H3: StageOrder is not overlap.
  // CPU: s2c2-cost-hb device=cpu func=h3_pipeline compute=8 storage=64 communication=64 synchronization=0 overlap=0 total=136
  // GPU: s2c2-cost-hb device=gpu func=h3_pipeline compute=1 storage=64 communication=64 synchronization=0 overlap=0 total=129
  func.func @h3_pipeline(%t: tensor<8xf32>) {
    %obj = stor.object : !stor.object<tensor<8xf32>>
    %ssd = stor.materialize %obj : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, ssd>
    %hbm = stor.materialize %obj : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, hbm>
    stor.pack %t into %ssd : tensor<8xf32>, !stor.buffer<tensor<8xf32>, ssd>
    sched.pipeline {
      sched.stage "compute" {
        %v = stor.unpack %ssd : !stor.buffer<tensor<8xf32>, ssd> -> tensor<8xf32>
        %y = comp.elemwise %v {kind = #comp.elemwise<silu>} : tensor<8xf32> -> tensor<8xf32>
        sched.yield
      }
      sched.stage "xfer" {
        %e = comm.stream %ssd, %hbm : !stor.buffer<tensor<8xf32>, ssd>, !stor.buffer<tensor<8xf32>, hbm> -> !sched.token
        sched.yield
      }
      sched.yield
    }
    return
  }

  // H5: explicit wait invents SW, so Compute →HB Comm. v0.2 GPU overlap=0.
  // Frozen v0.1 still credits the concurrent group (syntax heuristic).
  // CPU: s2c2-cost-hb device=cpu func=h5_wait_sibling compute=8 storage=64 communication=64 synchronization=1 overlap=0 total=137
  // GPU: s2c2-cost-hb device=gpu func=h5_wait_sibling compute=1 storage=64 communication=64 synchronization=1 overlap=0 total=130
  // V01: s2c2-cost device=gpu func=h5_wait_sibling compute=1 storage=64 communication=64 synchronization=1 overlap=1 total=129
  func.func @h5_wait_sibling(%t: tensor<8xf32>) {
    %obj = stor.object : !stor.object<tensor<8xf32>>
    %ssd = stor.materialize %obj : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, ssd>
    %hbm = stor.materialize %obj : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, hbm>
    stor.pack %t into %ssd : tensor<8xf32>, !stor.buffer<tensor<8xf32>, ssd>
    sched.concurrent {
      %t1 = sched.task {
        %v = stor.unpack %ssd : !stor.buffer<tensor<8xf32>, ssd> -> tensor<8xf32>
        %y = comp.elemwise %v {kind = #comp.elemwise<silu>} : tensor<8xf32> -> tensor<8xf32>
        sched.yield
      }
      %t2 = sched.task {
        sched.wait %t1 : !sched.token
        %e = comm.stream %ssd, %hbm : !stor.buffer<tensor<8xf32>, ssd>, !stor.buffer<tensor<8xf32>, hbm> -> !sched.token
        sched.yield
      }
      sched.yield
    }
    return
  }

  // H6: two IO streams, no wait. IO∥IO is 0 on GPU.
  // CPU: s2c2-cost-hb device=cpu func=h6_io_io compute=0 storage=128 communication=128 synchronization=0 overlap=0 total=256
  // GPU: s2c2-cost-hb device=gpu func=h6_io_io compute=0 storage=128 communication=128 synchronization=0 overlap=0 total=256
  func.func @h6_io_io(%t: tensor<8xf32>) {
    %a = stor.object : !stor.object<tensor<8xf32>>
    %b = stor.object : !stor.object<tensor<8xf32>>
    %a_ssd = stor.materialize %a : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, ssd>
    %a_hbm = stor.materialize %a : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, hbm>
    %b_ssd = stor.materialize %b : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, ssd>
    %b_hbm = stor.materialize %b : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, hbm>
    stor.pack %t into %a_ssd : tensor<8xf32>, !stor.buffer<tensor<8xf32>, ssd>
    stor.pack %t into %b_ssd : tensor<8xf32>, !stor.buffer<tensor<8xf32>, ssd>
    sched.concurrent {
      %t1 = sched.task {
        %e1 = comm.stream %a_ssd, %a_hbm : !stor.buffer<tensor<8xf32>, ssd>, !stor.buffer<tensor<8xf32>, hbm> -> !sched.token
        sched.yield
      }
      %t2 = sched.task {
        %e2 = comm.stream %b_ssd, %b_hbm : !stor.buffer<tensor<8xf32>, ssd>, !stor.buffer<tensor<8xf32>, hbm> -> !sched.token
        sched.yield
      }
      sched.yield
    }
    return
  }
}
