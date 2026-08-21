// RUN: s2c2-opt %s --s2c2-cost=device=cpu 2>&1 | FileCheck %s --check-prefix=CPU
// RUN: s2c2-opt %s --s2c2-cost=device=gpu 2>&1 | FileCheck %s --check-prefix=GPU

// v0.1 cost model: same S²C² IR, different device capability tables.
// Does not rewrite IR and does not redefine HB.
module {
  // K1: concurrent compute ∥ comm. CPU cannot overlap; GPU can.
  // CPU: s2c2-cost device=cpu func=k1_concurrent compute=8 storage=64 communication=64 synchronization=0 overlap=0 total=136
  // GPU: s2c2-cost device=gpu func=k1_concurrent compute=1 storage=64 communication=64 synchronization=0 overlap=1 total=128
  func.func @k1_concurrent(%t: tensor<8xf32>) {
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

  // K2: no concurrent region → overlap=0 on every device.
  // CPU: s2c2-cost device=cpu func=k2_sequential compute=8 storage=0 communication=0 synchronization=0 overlap=0 total=8
  // GPU: s2c2-cost device=gpu func=k2_sequential compute=1 storage=0 communication=0 synchronization=0 overlap=0 total=1
  func.func @k2_sequential(%t: tensor<8xf32>) -> tensor<8xf32> {
    %y = comp.elemwise %t {kind = #comp.elemwise<silu>} : tensor<8xf32> -> tensor<8xf32>
    return %y : tensor<8xf32>
  }

  // K3: StageOrder is sequential. GPU canOverlap does not credit across stages.
  // CPU: s2c2-cost device=cpu func=k3_pipeline compute=8 storage=64 communication=64 synchronization=0 overlap=0 total=136
  // GPU: s2c2-cost device=gpu func=k3_pipeline compute=1 storage=64 communication=64 synchronization=0 overlap=0 total=129
  func.func @k3_pipeline(%t: tensor<8xf32>) {
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

  // K4: explicit wait is synchronization, not overlap.
  // CPU: s2c2-cost device=cpu func=k4_wait compute=0 storage=64 communication=64 synchronization=1 overlap=0 total=129
  // GPU: s2c2-cost device=gpu func=k4_wait compute=0 storage=64 communication=64 synchronization=1 overlap=0 total=129
  func.func @k4_wait(%t: tensor<8xf32>) {
    %obj = stor.object : !stor.object<tensor<8xf32>>
    %ssd = stor.materialize %obj : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, ssd>
    %hbm = stor.materialize %obj : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, hbm>
    stor.pack %t into %ssd : tensor<8xf32>, !stor.buffer<tensor<8xf32>, ssd>
    %e = comm.stream %ssd, %hbm : !stor.buffer<tensor<8xf32>, ssd>, !stor.buffer<tensor<8xf32>, hbm> -> !sched.token
    sched.wait %e : !sched.token
    return
  }
}
