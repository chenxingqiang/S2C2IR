// RUN: s2c2-opt %s --s2c2-cost-cp=device=cpu 2>&1 | FileCheck %s --check-prefix=CPU
// RUN: s2c2-opt %s --s2c2-cost-cp=device=gpu 2>&1 | FileCheck %s --check-prefix=GPU
// RUN: s2c2-opt %s --s2c2-cost-hb=device=gpu 2>&1 | FileCheck %s --check-prefix=V02

// Cost Model v0.3: critical path + contention + capacity.
// Does not change --s2c2-cost (v0.1) or --s2c2-cost-hb (v0.2).
module {
  // C1: Compute ∥ IO, no HB. GPU pair-capable ⇒ contention=0.
  // CPU: s2c2-cost-cp device=cpu func=c1_concurrent critical_path=64 contention=8 capacity=64 total=136
  // GPU: s2c2-cost-cp device=gpu func=c1_concurrent critical_path=64 contention=0 capacity=64 total=128
  func.func @c1_concurrent(%t: tensor<8xf32>) {
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

  // C2: no concurrent region.
  // CPU: s2c2-cost-cp device=cpu func=c2_sequential critical_path=8 contention=0 capacity=0 total=8
  // GPU: s2c2-cost-cp device=gpu func=c2_sequential critical_path=1 contention=0 capacity=0 total=1
  func.func @c2_sequential(%t: tensor<8xf32>) -> tensor<8xf32> {
    %y = comp.elemwise %t {kind = #comp.elemwise<silu>} : tensor<8xf32> -> tensor<8xf32>
    return %y : tensor<8xf32>
  }

  // C3: StageOrder is already in T_HB.
  // CPU: s2c2-cost-cp device=cpu func=c3_pipeline critical_path=72 contention=0 capacity=64 total=136
  // GPU: s2c2-cost-cp device=gpu func=c3_pipeline critical_path=65 contention=0 capacity=64 total=129
  func.func @c3_pipeline(%t: tensor<8xf32>) {
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

  // C5: wait invents SW, so the chain is already in T_HB.
  // CPU: s2c2-cost-cp device=cpu func=c5_wait_sibling critical_path=73 contention=0 capacity=64 total=137
  // GPU: s2c2-cost-cp device=gpu func=c5_wait_sibling critical_path=66 contention=0 capacity=64 total=130
  func.func @c5_wait_sibling(%t: tensor<8xf32>) {
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

  // C6: two IO streams. IO∥IO serializes on GPU.
  // CPU: s2c2-cost-cp device=cpu func=c6_io_io critical_path=96 contention=32 capacity=128 total=256
  // GPU: s2c2-cost-cp device=gpu func=c6_io_io critical_path=96 contention=32 capacity=128 total=256
  func.func @c6_io_io(%t: tensor<8xf32>) {
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

  // C7: two sibling {compute; IO} chains. v0.2 pair credit is optimistic.
  // CPU: s2c2-cost-cp device=cpu func=c7_sibling_chains critical_path=72 contention=40 capacity=64 total=176
  // GPU: s2c2-cost-cp device=gpu func=c7_sibling_chains critical_path=65 contention=32 capacity=64 total=161
  // V02: s2c2-cost-hb device=gpu func=c7_sibling_chains compute=2 storage=64 communication=96 synchronization=0 overlap=2 total=160
  func.func @c7_sibling_chains(%t: tensor<8xf32>) {
    %obj = stor.object : !stor.object<tensor<8xf32>>
    %ssd = stor.materialize %obj : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, ssd>
    %hbm = stor.materialize %obj : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, hbm>
    stor.pack %t into %ssd : tensor<8xf32>, !stor.buffer<tensor<8xf32>, ssd>
    sched.concurrent {
      %t1 = sched.task {
        %v = stor.unpack %ssd : !stor.buffer<tensor<8xf32>, ssd> -> tensor<8xf32>
        %y = comp.elemwise %v {kind = #comp.elemwise<silu>} : tensor<8xf32> -> tensor<8xf32>
        %e = comm.stream %ssd, %hbm : !stor.buffer<tensor<8xf32>, ssd>, !stor.buffer<tensor<8xf32>, hbm> -> !sched.token
        sched.yield
      }
      %t2 = sched.task {
        %v2 = stor.unpack %ssd : !stor.buffer<tensor<8xf32>, ssd> -> tensor<8xf32>
        %y2 = comp.elemwise %v2 {kind = #comp.elemwise<silu>} : tensor<8xf32> -> tensor<8xf32>
        %e2 = comm.stream %ssd, %hbm : !stor.buffer<tensor<8xf32>, ssd>, !stor.buffer<tensor<8xf32>, hbm> -> !sched.token
        sched.yield
      }
      sched.yield
    }
    return
  }

  // C8: Compute ∥ DMA ∥ IO. v0.2 lumps DMA+IO as one communication pool.
  // CPU: s2c2-cost-cp device=cpu func=c8_three_kinds critical_path=68 contention=16 capacity=96 total=180
  // GPU: s2c2-cost-cp device=gpu func=c8_three_kinds critical_path=65 contention=0 capacity=96 total=161
  // V02: s2c2-cost-hb device=gpu func=c8_three_kinds compute=1 storage=96 communication=69 synchronization=0 overlap=1 total=165
  func.func @c8_three_kinds(%t: tensor<8xf32>) {
    %obj = stor.object : !stor.object<tensor<8xf32>>
    %ssd = stor.materialize %obj : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, ssd>
    %hbm = stor.materialize %obj : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, hbm>
    %dram = stor.materialize %obj : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, dram>
    stor.pack %t into %ssd : tensor<8xf32>, !stor.buffer<tensor<8xf32>, ssd>
    stor.pack %t into %hbm : tensor<8xf32>, !stor.buffer<tensor<8xf32>, hbm>
    sched.concurrent {
      %tc = sched.task {
        %v = stor.unpack %ssd : !stor.buffer<tensor<8xf32>, ssd> -> tensor<8xf32>
        %y = comp.elemwise %v {kind = #comp.elemwise<silu>} : tensor<8xf32> -> tensor<8xf32>
        sched.yield
      }
      %td = sched.task {
        %e = comm.stream %hbm, %dram {engine = #comm.engine<dma>} : !stor.buffer<tensor<8xf32>, hbm>, !stor.buffer<tensor<8xf32>, dram> -> !sched.token
        sched.yield
      }
      %ti = sched.task {
        %e2 = comm.stream %ssd, %hbm : !stor.buffer<tensor<8xf32>, ssd>, !stor.buffer<tensor<8xf32>, hbm> -> !sched.token
        sched.yield
      }
      sched.yield
    }
    return
  }
}
