// RUN: s2c2-opt %s --check-s2c2-execution
// RUN: s2c2-opt %s --s2c2-xform=kind=concurrent-reorder 2>&1 | grep s2c2-xform | FileCheck %s --check-prefix=OUT
// RUN: s2c2-opt %s --s2c2-enumerate 2>&1 | grep 'enumerate func=r4_same_program count=' | FileCheck %s --check-prefix=ENUM
// RUN: s2c2-opt %s --s2c2-xform=kind=concurrent-reorder --s2c2-enumerate 2>&1 | grep 'enumerate func=r4_same_program count=' | FileCheck %s --check-prefix=ENUM
// RUN: s2c2-opt %s --s2c2-xform=kind=concurrent-reorder | FileCheck %s --check-prefix=IR

// T_reorder: swap the first HB-independent concurrent sibling pair.
// Accept iff HB(P') = HB(P). Rebuild X'. Not Search.
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

  func.func @wait_sibling(%t: tensor<8xf32>) {
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
}

// OUT: s2c2-xform func=r4_same_program kind=concurrent-reorder
// OUT-NEXT: s2c2-xform func=r4_same_program accepted=1
// OUT-NEXT: s2c2-xform func=r4_same_program hb-eq=1
// OUT-NEXT: s2c2-xform func=r4_same_program x-rebuilt count=8
// OUT-NEXT: s2c2-xform func=wait_sibling kind=concurrent-reorder
// OUT-NEXT: s2c2-xform func=wait_sibling accepted=0
// OUT-NOT: winner=
// OUT-NOT: pi=
// OUT-NOT: s2c2-walk
// OUT-NOT: s2c2-search

// ENUM: enumerate func=r4_same_program count=8

// IR-LABEL: func.func @r4_same_program
// IR: sched.concurrent
// IR: comm.stream
// IR: stor.unpack
// IR-NOT: sched.pipeline
// IR-NOT: memref.copy
// IR-LABEL: func.func @wait_sibling
// IR: sched.concurrent
// IR: stor.unpack
// IR: sched.wait
// IR: comm.stream
