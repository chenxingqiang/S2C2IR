// RUN: s2c2-opt %s --check-s2c2-execution
// RUN: s2c2-opt %s --s2c2-enumerate 2>&1 | grep 'enumerate func=.* count=' | FileCheck %s --check-prefix=ENUM
// RUN: s2c2-opt %s --s2c2-argmin 2>&1 | grep 'argmin count=\|argmin sched=' | FileCheck %s --check-prefix=ARG
// RUN: s2c2-opt %s --s2c2-cost-cp=device=gpu 2>&1 | grep s2c2-cost-cp | FileCheck %s --check-prefix=GPU
// RUN: s2c2-opt %s --s2c2-xform=kind=concurrent-reorder 2>&1 | grep s2c2-xform | FileCheck %s --check-prefix=XF
// RUN: s2c2-opt %s --s2c2-xform=kind=concurrent-reorder | FileCheck %s --check-prefix=IR

// Pilot stand-ins for three research workloads. Shapes are scaled-down.
// Not a hardware benchmark. Not a new Search / Transform kind.
module {
  func.func @pilot_a_ssd_hbm_compute(%t: tensor<8xf32>) {
    %obj = stor.object : !stor.object<tensor<8xf32>>
    %ssd = stor.materialize %obj : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, ssd>
    %hbm = stor.materialize %obj : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, hbm>
    stor.pack %t into %ssd : tensor<8xf32>, !stor.buffer<tensor<8xf32>, ssd>
    %e = comm.stream %ssd, %hbm : !stor.buffer<tensor<8xf32>, ssd>, !stor.buffer<tensor<8xf32>, hbm> -> !sched.token
    sched.wait %e : !sched.token
    %v = stor.unpack %hbm : !stor.buffer<tensor<8xf32>, hbm> -> tensor<8xf32>
    %y = comp.elemwise %v {kind = #comp.elemwise<silu>} : tensor<8xf32> -> tensor<8xf32>
    return
  }

  func.func @pilot_b_compute_par_comm(%t: tensor<8xf32>) {
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

  func.func @pilot_c_pipeline_three_stage(%t: tensor<8xf32>) {
    %obj = stor.object : !stor.object<tensor<8xf32>>
    %ssd = stor.materialize %obj : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, ssd>
    %hbm = stor.materialize %obj : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, hbm>
    stor.pack %t into %ssd : tensor<8xf32>, !stor.buffer<tensor<8xf32>, ssd>
    sched.pipeline {
      sched.stage "prefetch" {
        %e = comm.stream %ssd, %hbm : !stor.buffer<tensor<8xf32>, ssd>, !stor.buffer<tensor<8xf32>, hbm> -> !sched.token
        sched.wait %e : !sched.token
        sched.yield
      }
      sched.stage "compute" {
        %v = stor.unpack %hbm : !stor.buffer<tensor<8xf32>, hbm> -> tensor<8xf32>
        %y = comp.elemwise %v {kind = #comp.elemwise<silu>} : tensor<8xf32> -> tensor<8xf32>
        stor.pack %y into %hbm : tensor<8xf32>, !stor.buffer<tensor<8xf32>, hbm>
        sched.yield
      }
      sched.stage "writeback" {
        %e2 = comm.stream %hbm, %ssd : !stor.buffer<tensor<8xf32>, hbm>, !stor.buffer<tensor<8xf32>, ssd> -> !sched.token
        sched.yield
      }
      sched.yield
    }
    return
  }
}

// ENUM: enumerate func=pilot_a_ssd_hbm_compute count=8
// ENUM: enumerate func=pilot_b_compute_par_comm count=8
// ENUM: enumerate func=pilot_c_pipeline_three_stage count=8

// ARG: s2c2-argmin func=pilot_a_ssd_hbm_compute argmin count=4
// ARG: s2c2-argmin func=pilot_a_ssd_hbm_compute argmin sched=gpu-async map=default device=gpu total=130
// ARG: s2c2-argmin func=pilot_b_compute_par_comm argmin count=4
// ARG: s2c2-argmin func=pilot_b_compute_par_comm argmin sched=gpu-async map=default device=gpu total=128
// ARG: s2c2-argmin func=pilot_c_pipeline_three_stage argmin count=2
// ARG: s2c2-argmin func=pilot_c_pipeline_three_stage argmin sched=gpu-async map=default device=gpu total=163

// GPU: s2c2-cost-cp device=gpu func=pilot_a_ssd_hbm_compute critical_path=66 contention=0 capacity=64 total=130
// GPU: s2c2-cost-cp device=gpu func=pilot_b_compute_par_comm critical_path=64 contention=0 capacity=64 total=128
// GPU: s2c2-cost-cp device=gpu func=pilot_c_pipeline_three_stage critical_path=99 contention=0 capacity=64 total=163

// XF: s2c2-xform func=pilot_a_ssd_hbm_compute accepted=0
// XF: s2c2-xform func=pilot_b_compute_par_comm accepted=1
// XF: s2c2-xform func=pilot_b_compute_par_comm hb-eq=1
// XF: s2c2-xform func=pilot_b_compute_par_comm x-rebuilt count=8
// XF: s2c2-xform func=pilot_c_pipeline_three_stage accepted=0
// XF-NOT: s2c2-search

// IR-LABEL: func.func @pilot_a_ssd_hbm_compute
// IR: comm.stream
// IR: sched.wait
// IR: stor.unpack
// IR-LABEL: func.func @pilot_b_compute_par_comm
// IR: sched.concurrent
// IR: comm.stream
// IR: stor.unpack
// IR-LABEL: func.func @pilot_c_pipeline_three_stage
// IR: sched.pipeline
// IR: sched.stage "prefetch"
// IR: sched.stage "compute"
// IR: sched.stage "writeback"
