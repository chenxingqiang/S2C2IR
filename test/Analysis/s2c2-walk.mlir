// RUN: s2c2-opt %s --check-s2c2-execution
// RUN: s2c2-opt %s --s2c2-walk 2>&1 | grep s2c2-walk | FileCheck %s --check-prefix=F0
// RUN: s2c2-opt %s --s2c2-walk=devices=cpu,gpu 2>&1 | grep s2c2-walk | FileCheck %s --check-prefix=DTEST
// RUN: s2c2-opt %s --s2c2-walk=restart=false 2>&1 | grep s2c2-walk | FileCheck %s --check-prefix=STOP
// RUN: s2c2-opt %s --s2c2-walk="devices=cpu,gpu restart=false" 2>&1 | grep s2c2-walk | FileCheck %s --check-prefix=STOPD
// RUN: s2c2-opt %s --s2c2-walk=nxt=pareto 2>&1 | grep s2c2-walk | FileCheck %s --check-prefix=PARETO
// RUN: s2c2-opt %s --s2c2-walk="nxt=pareto restart=false" 2>&1 | grep s2c2-walk | FileCheck %s --check-prefix=PSTOP
// RUN: s2c2-opt %s --s2c2-walk | FileCheck %s --check-prefix=IR
// RUN: s2c2-opt %s --s2c2-argmin 2>&1 | grep 'argmin count\|argmin sched\|pareto count' | FileCheck %s --check-prefix=AMIN

// Hamming-1 inhabitant: N=N_1, S=StartFirst, Rst=StartUnused, Nxt=first(Best).
// Nxt is total: F0-NEXT locks every decision as step or localstop.
// Does not rewrite P. After Complete, ArgMin equals --s2c2-argmin.
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

// F0: s2c2-walk func=r4_same_program start sched=cpu-seq map=default device=cpu
// F0-NEXT: s2c2-walk func=r4_same_program step sched=cpu-seq map=default device=cim total=129
// F0-NEXT: s2c2-walk func=r4_same_program step sched=cpu-seq map=t5 device=cim total=129
// F0-NEXT: s2c2-walk func=r4_same_program step sched=cpu-seq map=t5 device=cpu total=136
// F0-NEXT: s2c2-walk func=r4_same_program localstop accepted=4
// F0-NEXT: s2c2-walk func=r4_same_program restart sched=gpu-async map=default device=gpu
// F0-NEXT: s2c2-walk func=r4_same_program step sched=gpu-async map=t5 device=gpu total=128
// F0-NEXT: s2c2-walk func=r4_same_program localstop accepted=6
// F0-NEXT: s2c2-walk func=r4_same_program restart sched=npu-staged-dma map=default device=npu
// F0-NEXT: s2c2-walk func=r4_same_program step sched=npu-staged-dma map=t5 device=npu total=128
// F0-NEXT: s2c2-walk func=r4_same_program complete accepted=8
// F0-NEXT: s2c2-walk func=r4_same_program argmin count=4
// F0-NEXT: s2c2-walk func=r4_same_program argmin sched=gpu-async map=default device=gpu total=128
// F0-NEXT: s2c2-walk func=r4_same_program argmin sched=gpu-async map=t5 device=gpu total=128
// F0-NEXT: s2c2-walk func=r4_same_program argmin sched=npu-staged-dma map=default device=npu total=128
// F0-NEXT: s2c2-walk func=r4_same_program argmin sched=npu-staged-dma map=t5 device=npu total=128
// F0-NOT: winner=
// F0-NOT: pi=
// F0-NOT: error
// F0-NOT: undefined

// DTEST: s2c2-walk func=r4_same_program start sched=cpu-seq map=default device=cpu
// DTEST-NEXT: s2c2-walk func=r4_same_program step sched=cpu-seq map=t5 device=cpu total=136
// DTEST-NEXT: s2c2-walk func=r4_same_program localstop accepted=2
// DTEST-NEXT: s2c2-walk func=r4_same_program restart sched=gpu-async map=default device=gpu
// DTEST-NEXT: s2c2-walk func=r4_same_program step sched=gpu-async map=t5 device=gpu total=128
// DTEST-NEXT: s2c2-walk func=r4_same_program complete accepted=4
// DTEST-NEXT: s2c2-walk func=r4_same_program argmin count=2
// DTEST-NEXT: s2c2-walk func=r4_same_program argmin sched=gpu-async map=default device=gpu total=128
// DTEST-NEXT: s2c2-walk func=r4_same_program argmin sched=gpu-async map=t5 device=gpu total=128
// DTEST-NOT: winner=
// DTEST-NOT: pi=

// IR-LABEL: func.func @r4_same_program
// IR: sched.concurrent
// IR-NOT: memref.copy

// AMIN: argmin count=4
// AMIN: argmin sched=gpu-async map=default device=gpu total=128
// AMIN: pareto count=4

// Nxt_P = first(Pareto(Frontier)). On F_0/@r4, Cost⃗ is contention-monotone
// so the path equals W1; Complete Pareto matches --s2c2-argmin.
// PARETO: s2c2-walk nxt=pareto
// PARETO-NEXT: s2c2-walk nxt-oracle incomparable first(Best)!=first(Pareto)
// PARETO-NEXT: s2c2-walk func=r4_same_program start sched=cpu-seq map=default device=cpu
// PARETO-NEXT: s2c2-walk func=r4_same_program step sched=cpu-seq map=default device=cim total=129
// PARETO-NEXT: s2c2-walk func=r4_same_program step sched=cpu-seq map=t5 device=cim total=129
// PARETO-NEXT: s2c2-walk func=r4_same_program step sched=cpu-seq map=t5 device=cpu total=136
// PARETO-NEXT: s2c2-walk func=r4_same_program localstop accepted=4
// PARETO-NEXT: s2c2-walk func=r4_same_program restart sched=gpu-async map=default device=gpu
// PARETO-NEXT: s2c2-walk func=r4_same_program step sched=gpu-async map=t5 device=gpu total=128
// PARETO-NEXT: s2c2-walk func=r4_same_program localstop accepted=6
// PARETO-NEXT: s2c2-walk func=r4_same_program restart sched=npu-staged-dma map=default device=npu
// PARETO-NEXT: s2c2-walk func=r4_same_program step sched=npu-staged-dma map=t5 device=npu total=128
// PARETO-NEXT: s2c2-walk func=r4_same_program complete accepted=8
// PARETO-NEXT: s2c2-walk func=r4_same_program argmin count=4
// PARETO-NEXT: s2c2-walk func=r4_same_program argmin sched=gpu-async map=default device=gpu total=128
// PARETO-NEXT: s2c2-walk func=r4_same_program argmin sched=gpu-async map=t5 device=gpu total=128
// PARETO-NEXT: s2c2-walk func=r4_same_program argmin sched=npu-staged-dma map=default device=npu total=128
// PARETO-NEXT: s2c2-walk func=r4_same_program argmin sched=npu-staged-dma map=t5 device=npu total=128
// PARETO-NEXT: s2c2-walk func=r4_same_program pareto count=4
// PARETO-NEXT: s2c2-walk func=r4_same_program pareto sched=gpu-async map=default device=gpu critical_path=64 contention=0 capacity=64
// PARETO-NEXT: s2c2-walk func=r4_same_program pareto sched=gpu-async map=t5 device=gpu critical_path=64 contention=0 capacity=64
// PARETO-NEXT: s2c2-walk func=r4_same_program pareto sched=npu-staged-dma map=default device=npu critical_path=64 contention=0 capacity=64
// PARETO-NEXT: s2c2-walk func=r4_same_program pareto sched=npu-staged-dma map=t5 device=npu critical_path=64 contention=0 capacity=64
// PARETO-NOT: winner=
// PARETO-NOT: pi=

// PSTOP: s2c2-walk nxt=pareto
// PSTOP-NEXT: s2c2-walk nxt-oracle incomparable first(Best)!=first(Pareto)
// PSTOP-NEXT: s2c2-walk func=r4_same_program start sched=cpu-seq map=default device=cpu
// PSTOP-NEXT: s2c2-walk func=r4_same_program step sched=cpu-seq map=default device=cim total=129
// PSTOP-NEXT: s2c2-walk func=r4_same_program step sched=cpu-seq map=t5 device=cim total=129
// PSTOP-NEXT: s2c2-walk func=r4_same_program step sched=cpu-seq map=t5 device=cpu total=136
// PSTOP-NEXT: s2c2-walk func=r4_same_program localstop accepted=4
// PSTOP-NEXT: s2c2-walk func=r4_same_program argmin count=2
// PSTOP-NEXT: s2c2-walk func=r4_same_program argmin sched=cpu-seq map=default device=cim total=129
// PSTOP-NEXT: s2c2-walk func=r4_same_program argmin sched=cpu-seq map=t5 device=cim total=129
// PSTOP-NEXT: s2c2-walk func=r4_same_program pareto count=2
// PSTOP-NEXT: s2c2-walk func=r4_same_program pareto sched=cpu-seq map=default device=cim critical_path=64 contention=1 capacity=64
// PSTOP-NEXT: s2c2-walk func=r4_same_program pareto sched=cpu-seq map=t5 device=cim critical_path=64 contention=1 capacity=64
// PSTOP-NOT: complete
// PSTOP-NOT: restart
// PSTOP-NOT: gpu-async
// PSTOP-NOT: winner=
// PSTOP-NOT: pi=

// One Hamming-1 segment: ArgMin(Accepted)=129 ≠ ArgMin_F=128.
// STOP: s2c2-walk func=r4_same_program start sched=cpu-seq map=default device=cpu
// STOP-NEXT: s2c2-walk func=r4_same_program step sched=cpu-seq map=default device=cim total=129
// STOP-NEXT: s2c2-walk func=r4_same_program step sched=cpu-seq map=t5 device=cim total=129
// STOP-NEXT: s2c2-walk func=r4_same_program step sched=cpu-seq map=t5 device=cpu total=136
// STOP-NEXT: s2c2-walk func=r4_same_program localstop accepted=4
// STOP-NEXT: s2c2-walk func=r4_same_program argmin count=2
// STOP-NEXT: s2c2-walk func=r4_same_program argmin sched=cpu-seq map=default device=cim total=129
// STOP-NEXT: s2c2-walk func=r4_same_program argmin sched=cpu-seq map=t5 device=cim total=129
// STOP-NOT: complete
// STOP-NOT: restart
// STOP-NOT: gpu-async
// STOP-NOT: npu-staged-dma
// STOP-NOT: winner=
// STOP-NOT: pi=

// STOPD: s2c2-walk func=r4_same_program start sched=cpu-seq map=default device=cpu
// STOPD-NEXT: s2c2-walk func=r4_same_program step sched=cpu-seq map=t5 device=cpu total=136
// STOPD-NEXT: s2c2-walk func=r4_same_program localstop accepted=2
// STOPD-NEXT: s2c2-walk func=r4_same_program argmin count=2
// STOPD-NEXT: s2c2-walk func=r4_same_program argmin sched=cpu-seq map=default device=cpu total=136
// STOPD-NEXT: s2c2-walk func=r4_same_program argmin sched=cpu-seq map=t5 device=cpu total=136
// STOPD-NOT: complete
// STOPD-NOT: restart
// STOPD-NOT: gpu-async
// STOPD-NOT: winner=
// STOPD-NOT: pi=
