// RUN: s2c2-opt %s --check-s2c2-execution
// RUN: s2c2-opt %s --s2c2-xform 2>&1 | grep s2c2-xform | FileCheck %s --check-prefix=ID
// RUN: s2c2-opt %s --s2c2-xform=kind=id 2>&1 | grep s2c2-xform | FileCheck %s --check-prefix=ID
// RUN: s2c2-opt %s --s2c2-enumerate 2>&1 | grep 'enumerate func=.* count=' | FileCheck %s --check-prefix=ENUM
// RUN: s2c2-opt %s --s2c2-xform | FileCheck %s --check-prefix=IR

// T_id: P' = P. HB(P') = HB(P). X' is rebuilt, not reused.
// Not Search, not Concurrent → Pipeline.
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

// ID: s2c2-xform func=r4_same_program kind=id
// ID-NEXT: s2c2-xform func=r4_same_program hb-eq=1
// ID-NEXT: s2c2-xform func=r4_same_program x-rebuilt count=8
// ID-NOT: winner=
// ID-NOT: pi=
// ID-NOT: s2c2-walk
// ID-NOT: s2c2-search

// ENUM: enumerate func=r4_same_program count=8

// IR-LABEL: func.func @r4_same_program
// IR: sched.concurrent
// IR-NOT: sched.pipeline
// IR-NOT: memref.copy
