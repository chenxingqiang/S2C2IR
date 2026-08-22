// RUN: s2c2-opt %s --check-s2c2-execution
// RUN: s2c2-opt %s --s2c2-argmin 2>&1 | grep s2c2-argmin | FileCheck %s --check-prefix=F0
// RUN: s2c2-opt %s --s2c2-argmin=devices=cpu,gpu 2>&1 | grep s2c2-argmin | FileCheck %s --check-prefix=DTEST --implicit-check-not=device=npu --implicit-check-not=device=cim --implicit-check-not=winner= --implicit-check-not=pi=
// RUN: s2c2-opt %s --s2c2-argmin | FileCheck %s --check-prefix=IR
// RUN: s2c2-opt %s --s2c2-cost-cp=device=gpu 2>&1 | FileCheck %s --check-prefix=CP

// ArgMin_F / Pareto_F listing over Enum_F = R ∩ F.
// Reuses frozen Score_3. Does not rewrite, pick a unique M*, or print π.
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

// A1: Enum_F order, frozen Score_3 per device.
// cpu=136, cim=129, gpu=128, npu=128. |R ∩ F_0| = 8.
// F0: s2c2-argmin func=r4_same_program enum=8
// F0-NEXT: s2c2-argmin func=r4_same_program sched=cpu-seq map=default device=cpu critical_path=64 contention=8 capacity=64 total=136
// F0-NEXT: s2c2-argmin func=r4_same_program sched=cpu-seq map=default device=cim critical_path=64 contention=1 capacity=64 total=129
// F0-NEXT: s2c2-argmin func=r4_same_program sched=cpu-seq map=t5 device=cpu critical_path=64 contention=8 capacity=64 total=136
// F0-NEXT: s2c2-argmin func=r4_same_program sched=cpu-seq map=t5 device=cim critical_path=64 contention=1 capacity=64 total=129
// F0-NEXT: s2c2-argmin func=r4_same_program sched=gpu-async map=default device=gpu critical_path=64 contention=0 capacity=64 total=128
// F0-NEXT: s2c2-argmin func=r4_same_program sched=gpu-async map=t5 device=gpu critical_path=64 contention=0 capacity=64 total=128
// F0-NEXT: s2c2-argmin func=r4_same_program sched=npu-staged-dma map=default device=npu critical_path=64 contention=0 capacity=64 total=128
// F0-NEXT: s2c2-argmin func=r4_same_program sched=npu-staged-dma map=t5 device=npu critical_path=64 contention=0 capacity=64 total=128
// A2: ArgMin is a set. Ties stay ties (gpu and npu, both maps).
// F0-NEXT: s2c2-argmin func=r4_same_program argmin count=4
// F0-NEXT: s2c2-argmin func=r4_same_program argmin sched=gpu-async map=default device=gpu total=128
// F0-NEXT: s2c2-argmin func=r4_same_program argmin sched=gpu-async map=t5 device=gpu total=128
// F0-NEXT: s2c2-argmin func=r4_same_program argmin sched=npu-staged-dma map=default device=npu total=128
// F0-NEXT: s2c2-argmin func=r4_same_program argmin sched=npu-staged-dma map=t5 device=npu total=128
// A3: Pareto over (T_HB, contention, capacity); total is not a fourth axis.
// F0-NEXT: s2c2-argmin func=r4_same_program pareto count=4
// F0-NEXT: s2c2-argmin func=r4_same_program pareto sched=gpu-async map=default device=gpu critical_path=64 contention=0 capacity=64
// F0-NEXT: s2c2-argmin func=r4_same_program pareto sched=gpu-async map=t5 device=gpu critical_path=64 contention=0 capacity=64
// F0-NEXT: s2c2-argmin func=r4_same_program pareto sched=npu-staged-dma map=default device=npu critical_path=64 contention=0 capacity=64
// F0-NEXT: s2c2-argmin func=r4_same_program pareto sched=npu-staged-dma map=t5 device=npu critical_path=64 contention=0 capacity=64
// Dominated devices are not in ArgMin / Pareto.
// F0-NOT: argmin {{.*}} device=cpu
// F0-NOT: argmin {{.*}} device=cim
// F0-NOT: pareto {{.*}} device=cpu
// F0-NOT: pareto {{.*}} device=cim
// A4: no unique winner, no π, no pipeline rewrite label.
// F0-NOT: winner=
// F0-NOT: m*=
// F0-NOT: pi=
// F0-NOT: sched=pipeline

// S1 on D_test={cpu,gpu}: every scalar minimum uses gpu (128 < 136).
// DTEST: s2c2-argmin func=r4_same_program enum=4
// DTEST: sched=cpu-seq map=default device=cpu {{.*}} total=136
// DTEST: sched=gpu-async map=default device=gpu {{.*}} total=128
// DTEST: s2c2-argmin func=r4_same_program argmin count=2
// DTEST-NEXT: s2c2-argmin func=r4_same_program argmin sched=gpu-async map=default device=gpu total=128
// DTEST-NEXT: s2c2-argmin func=r4_same_program argmin sched=gpu-async map=t5 device=gpu total=128
// DTEST: s2c2-argmin func=r4_same_program pareto count=2
// DTEST-NEXT: s2c2-argmin func=r4_same_program pareto sched=gpu-async map=default device=gpu critical_path=64 contention=0 capacity=64
// DTEST-NEXT: s2c2-argmin func=r4_same_program pareto sched=gpu-async map=t5 device=gpu critical_path=64 contention=0 capacity=64
// DTEST-NOT: argmin {{.*}} device=cpu
// DTEST-NOT: device=npu
// DTEST-NOT: device=cim
// DTEST-NOT: winner=
// DTEST-NOT: pi=

// A5: listing is not a rewrite. A6: shared Score_3 matches --s2c2-cost-cp.
// IR-LABEL: func.func @r4_same_program
// IR: sched.concurrent
// IR-NOT: memref.copy
// CP: s2c2-cost-cp device=gpu func=r4_same_program critical_path=64 contention=0 capacity=64 total=128
