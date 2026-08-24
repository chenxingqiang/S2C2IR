// RUN: s2c2-opt %s --s2c2-capability-schedule=device=rtx4090 --check-s2c2-execution 2>&1 | grep capability-schedule | FileCheck %s --check-prefix=GPU-LOG
// RUN: s2c2-opt %s --s2c2-capability-schedule=device=npu-demo --check-s2c2-execution 2>&1 | grep capability-schedule | FileCheck %s --check-prefix=NPU-LOG
// RUN: s2c2-opt %s --s2c2-capability-schedule=device=rtx4090 --check-s2c2-execution | FileCheck %s --check-prefix=GPU
// RUN: s2c2-opt %s --s2c2-capability-schedule=device=npu-demo --check-s2c2-execution | FileCheck %s --check-prefix=NPU

// Same S²C² IR, two CapabilityProfiles, two legal schedules.
// Destructive serialize requires applicable=yes AND relation=serial.
// arm_specific evidence is queryable and is not a global rule.
// Concurrent → parent IR order is allowed. No invented sibling wait.
// Pipeline StageOrder is preserved. Not Cost v0.4.

// GPU-LOG: pair=C||HtoD relation=parallel
// GPU-LOG: applicable=no
// GPU-LOG: decision=keep
// GPU-LOG: pair=C_silu||C_gemm relation=serial
// GPU-LOG: confidence=arm_specific
// GPU-LOG: applicable=no
// GPU-LOG: decision=keep
// GPU-LOG: pair=C||C relation=serial
// GPU-LOG: applicable=yes
// GPU-LOG: decision=serialize
// GPU-LOG: semantics=unchanged
// GPU-LOG: v3=not-claimed
// GPU-LOG: cost=unchanged

// NPU-LOG: pair=C||HtoD relation=parallel
// NPU-LOG: decision=keep
// NPU-LOG: pair=C_silu||C_gemm relation=parallel
// NPU-LOG: applicable=no
// NPU-LOG: decision=keep
// NPU-LOG: pair=C||C relation=parallel
// NPU-LOG: applicable=no
// NPU-LOG: decision=keep
// NPU-LOG: semantics=unchanged
// NPU-LOG: cost=unchanged

module {
  // GPU-LABEL: func.func @compute_par_htod
  // NPU-LABEL: func.func @compute_par_htod
  // GPU: sched.concurrent
  // GPU: sched.task
  // GPU: comp.elemwise
  // GPU: sched.task
  // GPU: comm.stream
  // NPU: sched.concurrent
  func.func @compute_par_htod(%x: tensor<8xf32>) {
    %obj = stor.object : !stor.object<tensor<8xf32>>
    %host = stor.materialize %obj : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, host>
    %hbm = stor.materialize %obj : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, hbm>
    stor.pack %x into %host : tensor<8xf32>, !stor.buffer<tensor<8xf32>, host>
    sched.concurrent {
      %tc = sched.task {
        %v = stor.unpack %host : !stor.buffer<tensor<8xf32>, host> -> tensor<8xf32>
        %y = comp.elemwise %v {kind = #comp.elemwise<silu>} : tensor<8xf32> -> tensor<8xf32>
        sched.yield
      }
      %ts = sched.task {
        %e = comm.stream %host, %hbm : !stor.buffer<tensor<8xf32>, host>, !stor.buffer<tensor<8xf32>, hbm> -> !sched.token
        sched.yield
      }
      sched.yield
    }
    return
  }

  // arm_specific SiLU||GEMM stays concurrent on both profiles.
  // GPU-LABEL: func.func @silu_par_gemm
  // NPU-LABEL: func.func @silu_par_gemm
  // GPU: sched.concurrent
  // GPU: comp.elemwise
  // GPU: comp.matmul
  // GPU-NOT: sched.wait
  // NPU: sched.concurrent
  // NPU: comp.elemwise
  // NPU: comp.matmul
  func.func @silu_par_gemm(%x: tensor<8xf32>, %w: tensor<8x8xf32>) {
    sched.concurrent {
      %ta = sched.task {
        %y = comp.elemwise %x {kind = #comp.elemwise<silu>} : tensor<8xf32> -> tensor<8xf32>
        sched.yield
      }
      %tb = sched.task {
        %z = comp.matmul %x, %w : tensor<8xf32>, tensor<8x8xf32> -> tensor<8xf32>
        sched.yield
      }
      sched.yield
    }
    return
  }

  // Measured C||C is applicable: 4090 serializes, npu-demo keeps.
  // GPU-LABEL: func.func @gemm_par_gemm
  // NPU-LABEL: func.func @gemm_par_gemm
  // GPU: sched.task
  // GPU: comp.matmul
  // GPU: sched.task
  // GPU: comp.matmul
  // GPU-NOT: sched.concurrent
  // GPU-NOT: sched.wait
  // NPU: sched.concurrent
  // NPU: comp.matmul
  func.func @gemm_par_gemm(%x: tensor<8xf32>, %w: tensor<8x8xf32>) {
    sched.concurrent {
      %ta = sched.task {
        %y = comp.matmul %x, %w : tensor<8xf32>, tensor<8x8xf32> -> tensor<8xf32>
        sched.yield
      }
      %tb = sched.task {
        %z = comp.matmul %x, %w : tensor<8xf32>, tensor<8x8xf32> -> tensor<8xf32>
        sched.yield
      }
      sched.yield
    }
    return
  }

  // StageOrder must not be broken on either profile.
  // GPU-LABEL: func.func @pipeline_stageorder
  // NPU-LABEL: func.func @pipeline_stageorder
  // GPU: sched.pipeline
  // GPU: sched.stage "prefetch"
  // GPU: stor.pack
  // GPU: sched.stage "compute"
  // GPU: stor.unpack
  // NPU: sched.pipeline
  // NPU: sched.stage "prefetch"
  // NPU: sched.stage "compute"
  func.func @pipeline_stageorder(%x: tensor<8xf32>) -> tensor<8xf32> {
    %obj = stor.object : !stor.object<tensor<8xf32>>
    %hbm = stor.materialize %obj : !stor.object<tensor<8xf32>> -> !stor.buffer<tensor<8xf32>, hbm>
    sched.pipeline {
      sched.stage "prefetch" {
        stor.pack %x into %hbm : tensor<8xf32>, !stor.buffer<tensor<8xf32>, hbm>
        sched.yield
      }
      sched.stage "compute" {
        %v = stor.unpack %hbm : !stor.buffer<tensor<8xf32>, hbm> -> tensor<8xf32>
        sched.yield
      }
      sched.yield
    }
    %out = stor.unpack %hbm : !stor.buffer<tensor<8xf32>, hbm> -> tensor<8xf32>
    return %out : tensor<8xf32>
  }
}
