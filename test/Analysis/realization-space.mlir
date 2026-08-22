// RUN: s2c2-opt %s --check-s2c2-execution
// RUN: s2c2-opt %s --s2c2-cost-cp=device=cpu 2>&1 | FileCheck %s --check-prefix=CPU
// RUN: s2c2-opt %s --s2c2-cost-cp=device=gpu 2>&1 | FileCheck %s --check-prefix=GPU
// RUN: s2c2-opt %s --s2c2-lower 2>&1 | FileCheck %s --check-prefix=SEQ

// Realization Space v0.4.0: same P, two legal (device) scores.
// Does not search. Does not change --s2c2-cost / --s2c2-cost-hb / --s2c2-cost-cp.
// R(P, D) requires HB_M = HB_source (equality), not HB_source ⊆ HB_M.
// R4: Score_3(cpu) != Score_3(gpu) on HB-unordered Compute || IO.
// R5 (design): rewriting this Concurrent as Pipeline would add StageOrder,
// so HB_candidate != HB_source and that candidate is not in R.
// S1 (design): argmin_M Score_3.total over {cpu,gpu} is gpu (128 < 136).
// S3 (design): that Pipeline candidate is also outside the Search domain.
module {
  // CPU: s2c2-cost-cp device=cpu func=r4_same_program critical_path=64 contention=8 capacity=64 total=136
  // GPU: s2c2-cost-cp device=gpu func=r4_same_program critical_path=64 contention=0 capacity=64 total=128
  func.func @r4_same_program(%t: tensor<8xf32>) {
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
}

// SEQ-LABEL: func.func @r4_same_program
// SEQ: memref.copy
// SEQ-NOT: async.execute
// SEQ-NOT: sched.concurrent
// SEQ-NOT: comm.stream
