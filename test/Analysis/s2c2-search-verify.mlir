// RUN: s2c2-opt %s --s2c2-walk=verify 2>&1 | grep s2c2-walk | FileCheck %s --check-prefix=S1
// RUN: s2c2-opt %s --s2c2-walk=verify 2>&1 | grep s2c2-walk > %t.a
// RUN: s2c2-opt %s --s2c2-walk=verify 2>&1 | grep s2c2-walk > %t.b
// RUN: diff %t.a %t.b
// RUN: s2c2-opt %s --s2c2-walk=verify 2>&1 | grep s2c2-walk | FileCheck %s --check-prefix=S3
// RUN: s2c2-opt %s --s2c2-walk="verify=true restart=false" 2>&1 | grep s2c2-walk | FileCheck %s --check-prefix=S4
// RUN: s2c2-opt %s --s2c2-walk=verify 2>&1 | grep s2c2-walk | FileCheck %s --check-prefix=S5
// RUN: s2c2-opt %s --s2c2-walk=verify 2>&1 | grep s2c2-walk | FileCheck %s --check-prefix=S6
// RUN: s2c2-opt %s --s2c2-walk="verify=true nxt=pareto" 2>&1 | grep s2c2-walk | FileCheck %s --check-prefix=S7
// RUN: s2c2-opt %s --s2c2-walk=verify | FileCheck %s --check-prefix=S8
// RUN: s2c2-opt %s --s2c2-argmin 2>&1 | grep 'argmin count' | FileCheck %s --check-prefix=AMIN

// Search Verification S1–S8. verify is a witness switch, not a third Nxt.
module {
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

// S1: Nxt totality — every decision is step or localstop; nxt-total=1.
// S1: verify nxt-total=1
// S1: step
// S1: localstop
// S1-NOT: error
// S1-NOT: undefined

// S3: Complete ⇒ Accepted=X ⇒ ArgMin_F.
// S3: verify complete accepted=8 |X|=8
// S3: argmin count=4
// AMIN: argmin count=4

// S4: LocalStop ⇏ ArgMin_F.
// S4: verify localstop accepted=4 |X|=8
// S4: argmin count=2
// S4: total=129
// S4-NOT: complete
// S4-NOT: total=128

// S5: Restart ≠ Reset — accepted only grows.
// S5: localstop accepted=4
// S5: restart
// S5: localstop accepted=6
// S5: restart
// S5: complete accepted=8

// S6: State invariants after Install and Acc.
// S6: verify current-in-X=1 accepted-subseteq-scored=1 scored-subseteq-legal=1 legal=checked-cap-X=1 ok=1
// S6-NOT: verify {{.*}} ok=0

// S7: two Nxt inhabitants; fixture path still completes.
// S7: nxt=pareto
// S7: nxt-oracle incomparable first(Best)!=first(Pareto)
// S7: verify complete accepted=8 |X|=8
// S7: pareto count=4
// S7: verify ok=1

// S8: still selection, not rewrite.
// S8-LABEL: func.func @r4_same_program
// S8: sched.concurrent
// S8-NOT: memref.copy
// S8-NOT: winner=
// S8-NOT: pi=
