// RUN: s2c2-opt %s --check-s2c2-execution
// RUN: s2c2-opt %s --s2c2-enumerate 2>&1 | grep s2c2-enumerate | FileCheck %s --check-prefix=F0
// RUN: s2c2-opt %s --s2c2-enumerate=devices=cpu,gpu 2>&1 | grep s2c2-enumerate | FileCheck %s --check-prefix=DTEST
// RUN: s2c2-opt %s --s2c2-enumerate | FileCheck %s --check-prefix=IR

// Realization Enumerator listing: Output(M)=1 iff M ∈ R ∩ F.
// IsLegal is T1/T2/T3 profile pairing, not F-membership.
// Does not rewrite, score, or apply ArgMin / Pareto / Search.
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

// N10: R ∩ F_0 is the legal T1/T2/T3 pairings, F_0 product order.
// |F_0|=24 but count = |R ∩ F_0| = 8.
// F0: s2c2-enumerate func=r4_same_program count=8
// F0-NEXT: s2c2-enumerate func=r4_same_program sched=cpu-seq map=default device=cpu
// F0-NEXT: s2c2-enumerate func=r4_same_program sched=cpu-seq map=default device=cim
// F0-NEXT: s2c2-enumerate func=r4_same_program sched=cpu-seq map=t5 device=cpu
// F0-NEXT: s2c2-enumerate func=r4_same_program sched=cpu-seq map=t5 device=cim
// F0-NEXT: s2c2-enumerate func=r4_same_program sched=gpu-async map=default device=gpu
// F0-NEXT: s2c2-enumerate func=r4_same_program sched=gpu-async map=t5 device=gpu
// F0-NEXT: s2c2-enumerate func=r4_same_program sched=npu-staged-dma map=default device=npu
// F0-NEXT: s2c2-enumerate func=r4_same_program sched=npu-staged-dma map=t5 device=npu
// N9: members in F_0 that fail IsLegal are not emitted.
// F0-NOT: sched=cpu-seq map=default device=gpu
// F0-NOT: sched=gpu-async map=default device=cpu
// F0-NOT: sched=gpu-async map=default device=cim
// F0-NOT: sched=npu-staged-dma map=default device=cim
// F0-NOT: sched=npu-staged-dma map=t5 device=cim
// N4 / N5: no rewrite label, no π, no ArgMin / score.
// F0-NOT: sched=pipeline
// F0-NOT: pi=
// F0-NOT: argmin
// F0-NOT: total=

// N6: D_test={cpu,gpu} ∩ IsLegal = 4 (cpu-seq×{default,t5}×cpu + gpu-async×{default,t5}×gpu).
// DTEST: s2c2-enumerate func=r4_same_program count=4
// DTEST: sched=cpu-seq map=default device=cpu
// DTEST: sched=gpu-async map=default device=gpu
// DTEST-NOT: device=npu
// DTEST-NOT: device=cim
// DTEST-NOT: argmin

// IR is unchanged (listing is not a rewrite).
// IR-LABEL: func.func @r4_same_program
// IR: sched.concurrent
// IR-NOT: memref.copy
