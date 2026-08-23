// RUN: s2c2-opt %s --check-s2c2-execution
// RUN: s2c2-opt %s --s2c2-xform=kind=concurrent-reorder --s2c2-xform=kind=concurrent-reorder 2>&1 | grep s2c2-xform | FileCheck %s --check-prefix=RR
// RUN: s2c2-opt %s --s2c2-xform=kind=concurrent-reorder --s2c2-xform=kind=concurrent-reorder | FileCheck %s --check-prefix=RRIR
// RUN: s2c2-opt %s --s2c2-xform=kind=id --s2c2-xform=kind=concurrent-reorder | FileCheck %s --check-prefix=IRID
// RUN: s2c2-opt %s --s2c2-xform=kind=concurrent-reorder --s2c2-xform=kind=id | FileCheck %s --check-prefix=RID
// RUN: s2c2-opt %s --s2c2-xform=kind=concurrent-reorder --s2c2-xform=kind=concurrent-reorder --s2c2-enumerate 2>&1 | grep 'enumerate func=r4_same_program count=' | FileCheck %s --check-prefix=ENUM

// Coincidence witnesses: sequential Apply equals compose on IR
// only when both succeed or T_a = ⊥. Not a compose pass.
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

// RR: s2c2-xform func=r4_same_program kind=concurrent-reorder
// RR-NEXT: s2c2-xform func=r4_same_program accepted=1
// RR-NEXT: s2c2-xform func=r4_same_program hb-eq=1
// RR-NEXT: s2c2-xform func=r4_same_program x-rebuilt count=8
// RR-NEXT: s2c2-xform func=wait_sibling kind=concurrent-reorder
// RR-NEXT: s2c2-xform func=wait_sibling accepted=0
// RR-NEXT: s2c2-xform func=r4_same_program kind=concurrent-reorder
// RR-NEXT: s2c2-xform func=r4_same_program accepted=1
// RR-NEXT: s2c2-xform func=r4_same_program hb-eq=1
// RR-NEXT: s2c2-xform func=r4_same_program x-rebuilt count=8
// RR-NEXT: s2c2-xform func=wait_sibling kind=concurrent-reorder
// RR-NEXT: s2c2-xform func=wait_sibling accepted=0
// RR-NOT: compose
// RR-NOT: s2c2-search
// RR-NOT: winner=
// RR-NOT: pi=

// ENUM: enumerate func=r4_same_program count=8

// RRIR-LABEL: func.func @r4_same_program
// RRIR: sched.concurrent
// RRIR: stor.unpack
// RRIR: comm.stream
// RRIR-NOT: sched.pipeline
// RRIR-LABEL: func.func @wait_sibling
// RRIR: stor.unpack
// RRIR: sched.wait
// RRIR: comm.stream

// IRID-LABEL: func.func @r4_same_program
// IRID: sched.concurrent
// IRID: comm.stream
// IRID: stor.unpack
// IRID-LABEL: func.func @wait_sibling
// IRID: stor.unpack
// IRID: sched.wait

// RID-LABEL: func.func @r4_same_program
// RID: sched.concurrent
// RID: comm.stream
// RID: stor.unpack
// RID-LABEL: func.func @wait_sibling
// RID: stor.unpack
// RID: sched.wait
