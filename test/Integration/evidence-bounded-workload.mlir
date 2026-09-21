// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-workload-schedule-contract | FileCheck %s --check-prefix=CONTRACT
// RUN: s2c2-opt %s --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'workload-candidate|workload-schedule|candidate #' | FileCheck %s --check-prefix=GPU-LOG
// RUN: s2c2-opt %s --profile=910B --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'workload-candidate|workload-schedule|candidate #' | FileCheck %s --check-prefix=NPU-LOG
// RUN: s2c2-opt %s --profile=unknown --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'workload-candidate|workload-schedule|candidate #' | FileCheck %s --check-prefix=UNK-LOG
// RUN: s2c2-opt %s --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | FileCheck %s --check-prefix=GPU-PRETTY
// RUN: s2c2-opt %s --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2> %t.gpu.err | FileCheck %s --check-prefix=GPU
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-workload-schedule %t.gpu.err | FileCheck %s --check-prefix=GPU-AN
// RUN: s2c2-opt %s --profile=910B --s2c2-evidence-bounded-schedule --check-s2c2-execution 2> %t.npu.err | FileCheck %s --check-prefix=NPU
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-workload-schedule %t.npu.err | FileCheck %s --check-prefix=NPU-AN
// RUN: s2c2-opt %s --profile=unknown --s2c2-evidence-bounded-schedule --check-s2c2-execution 2> %t.unk.err | FileCheck %s --check-prefix=UNK
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-workload-schedule %t.unk.err | FileCheck %s --check-prefix=UNK-AN
// RUN: s2c2-opt %s --s2c2-evidence-bounded-schedule="profile=rtx4090 dump-schedule=%t.json" --check-s2c2-execution >/dev/null 2>&1
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-workload-schedule %t.json | FileCheck %s --check-prefix=GPU-AN
// RUN: s2c2-opt %s --profile=rtx4090 --s2c2-evidence-bounded-schedule --s2c2-lower | FileCheck %s --check-prefix=LOWER
// RUN: s2c2-opt %s --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution | grep -c sched.concurrent | FileCheck %s --check-prefix=GPU-N
// RUN: s2c2-opt %s --profile=910B --s2c2-evidence-bounded-schedule --check-s2c2-execution | grep -c sched.concurrent | FileCheck %s --check-prefix=NPU-N
// RUN: s2c2-opt %s --profile=unknown --s2c2-evidence-bounded-schedule --check-s2c2-execution | grep -c sched.concurrent | FileCheck %s --check-prefix=UNK-N
// RUN: s2c2-cuda-adapter --dry-run --workload-schedule 2>&1 | FileCheck %s --check-prefix=CUDA
// RUN: s2c2-ascend-adapter --dry-run --workload-schedule 2>&1 | FileCheck %s --check-prefix=ASCEND
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-ssd-mlp-wallclock %S/../../docs/design/v3-dataset/ssd-mlp-wallclock.log | FileCheck %s --check-prefix=RT
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-ssd-mlp-wallclock %S/../../docs/design/v3-dataset/ssd-mlp-wallclock-4090.log | FileCheck %s --check-prefix=RT4090

// Phase 3E: one semantic workload. IR does not encode keep/flatten/preserve.
// Compiler discovers three sched.concurrent candidates and decides.
// SSD → Host is sequential. Host→HBM || MLP is candidate #0 (KEEP overlap).
// 16MiB C||C is #1. 128MiB C||C is #2.
// unknown / unlicensed C||C is PRESERVE. Not Cost v0.4.

// CONTRACT: workload-schedule compiler-driven=yes
// CONTRACT: no-evidence => no-destructive-optimization
// CONTRACT: invariant semantic-ne-perf-serial
// CONTRACT: invariant capability-ne-rewrite
// CONTRACT: invariant scoped-ne-global
// CONTRACT: invariant underdetermined-preserve
// CONTRACT: invariant rewrite-preserves-hb
// CONTRACT: note not-handwritten-optimized-ir
// CONTRACT: note runtime-witness=ssd-mlp-wallclock
// CONTRACT: note storage-data-movement-overlap
// CONTRACT: cost=unchanged
// CONTRACT-NOT: Cost v0.4
// CONTRACT-NOT: password

// GPU-LOG: workload-candidate #0 pair=C||HtoD
// GPU-LOG-SAME: decision=KEEP
// GPU-LOG-SAME: reason=storage-communication-overlap
// GPU-LOG: workload-candidate #1 pair=C||C payload=16MiB
// GPU-LOG-SAME: decision=FLATTEN
// GPU-LOG-SAME: reason=licensed-compute-contention
// GPU-LOG: workload-candidate #2 pair=C||C payload=128MiB
// GPU-LOG-SAME: decision=FLATTEN
// GPU-LOG-SAME: reason=licensed-compute-contention
// GPU-LOG: workload-schedule candidates=3 keep=1 flatten=2 preserve=0

// GPU-PRETTY: candidate #0 : C || HtoD
// GPU-PRETTY-NEXT:     decision : KEEP
// GPU-PRETTY-NEXT:     reason   : storage communication overlap
// GPU-PRETTY: candidate #1 : C || C
// GPU-PRETTY-NEXT:     decision : FLATTEN
// GPU-PRETTY-NEXT:     reason   : licensed compute contention
// GPU-PRETTY: candidate #2 : C || C
// GPU-PRETTY-NEXT:     decision : FLATTEN
// GPU-PRETTY-NEXT:     reason   : licensed compute contention
// GPU-PRETTY: HB verification : --check-s2c2-execution
// GPU-PRETTY: lowering        : --s2c2-lower

// NPU-LOG: workload-candidate #0 pair=C||HtoD
// NPU-LOG-SAME: decision=KEEP
// NPU-LOG-SAME: reason=storage-communication-overlap
// NPU-LOG: workload-candidate #1 pair=C||C payload=16MiB
// NPU-LOG-SAME: decision=PRESERVE
// NPU-LOG-SAME: reason=rewrite-license-no
// NPU-LOG: workload-candidate #2 pair=C||C payload=128MiB
// NPU-LOG-SAME: decision=FLATTEN
// NPU-LOG-SAME: reason=licensed-compute-contention
// NPU-LOG: workload-schedule candidates=3 keep=1 flatten=1 preserve=1

// UNK-LOG: workload-candidate #0
// UNK-LOG-SAME: decision=PRESERVE
// UNK-LOG: workload-candidate #1
// UNK-LOG-SAME: decision=PRESERVE
// UNK-LOG: workload-candidate #2
// UNK-LOG-SAME: decision=PRESERVE
// UNK-LOG-NOT: decision=FLATTEN
// UNK-LOG-NOT: decision=KEEP
// UNK-LOG: workload-schedule candidates=3 keep=0 flatten=0 preserve=3

// GPU-AN: workload-schedule compiler-driven=yes
// GPU-AN: workload-schedule candidates=3
// GPU-AN: workload-schedule keep=1
// GPU-AN: workload-schedule flatten=2
// GPU-AN: workload-schedule preserve=0
// GPU-AN: note not-handwritten-optimized-ir
// GPU-AN: note runtime-witness=ssd-mlp-wallclock
// GPU-AN: cost=unchanged
// GPU-AN-NOT: Cost v0.4

// NPU-AN: workload-schedule candidates=3
// NPU-AN: workload-schedule keep=1
// NPU-AN: workload-schedule flatten=1
// NPU-AN: workload-schedule preserve=1
// NPU-AN: note not-handwritten-optimized-ir
// NPU-AN: cost=unchanged

// UNK-AN: workload-schedule candidates=3
// UNK-AN: workload-schedule keep=0
// UNK-AN: workload-schedule flatten=0
// UNK-AN: workload-schedule preserve=3
// UNK-AN-NOT: decision=FLATTEN
// UNK-AN-NOT: decision=KEEP
// UNK-AN: cost=unchanged

// GPU-N: 1
// NPU-N: 2
// UNK-N: 3

// CUDA: s2c2-cuda-adapter workload-schedule=1
// CUDA: s2c2-cuda-adapter workload-schedule source=s2c2-opt
// CUDA: s2c2-cuda-adapter workload-schedule note not-handwritten-optimized-ir
// CUDA: s2c2-cuda-adapter workload-schedule runtime-witness=ssd-mlp-wallclock
// CUDA: s2c2-cuda-adapter workload-schedule note compiler-chosen-t-evi
// CUDA: s2c2-cuda-adapter workload-schedule note storage-data-movement-overlap
// CUDA: s2c2-cuda-adapter workload-schedule cost=unchanged
// CUDA-NOT: Cost v0.4
// CUDA-NOT: password

// ASCEND: s2c2-ascend-adapter workload-schedule=1
// ASCEND: s2c2-ascend-adapter workload-schedule source=s2c2-opt
// ASCEND: s2c2-ascend-adapter workload-schedule note not-handwritten-optimized-ir
// ASCEND: s2c2-ascend-adapter workload-schedule runtime-witness=ssd-mlp-wallclock
// ASCEND: s2c2-ascend-adapter workload-schedule note compiler-chosen-t-evi
// ASCEND: s2c2-ascend-adapter workload-schedule note storage-data-movement-overlap
// ASCEND: s2c2-ascend-adapter workload-schedule cost=unchanged
// ASCEND-NOT: Cost v0.4

// RT: ssd-mlp-wallclock measured=yes
// RT: note t-opt-is-t-evi
// RT: cost=unchanged
// RT-NOT: Cost v0.4
// RT4090: ssd-mlp-wallclock measured=yes
// RT4090: note t-opt-is-t-evi
// RT4090: cost=unchanged
// RT4090-NOT: Cost v0.4

module {
  // One function: semantic schedule only. Compiler decides realization.
  // GPU-LABEL: func.func @ssd_stream_tiles
  // NPU-LABEL: func.func @ssd_stream_tiles
  // UNK-LABEL: func.func @ssd_stream_tiles
  // GPU: stor.transfer
  // GPU: sched.concurrent
  // GPU: comm.stream
  // GPU: comp.gated_mlp
  // GPU: sched.task
  // GPU: comp.elemwise
  // GPU-NOT: sched.wait
  // NPU: stor.transfer
  // NPU: sched.concurrent
  // NPU: comm.stream
  // NPU: comp.gated_mlp
  // NPU: sched.concurrent
  // NPU: comp.elemwise
  // NPU-NOT: sched.wait
  // UNK: stor.transfer
  // UNK: sched.concurrent
  // UNK: sched.concurrent
  // UNK: sched.concurrent
  // UNK-NOT: sched.wait
  // LOWER-LABEL: func.func @ssd_stream_tiles
  // LOWER: memref.copy
  // LOWER: linalg.matmul
  // LOWER-NOT: sched.concurrent
  // LOWER-NOT: comm.stream
  // LOWER-NOT: comp.gated_mlp
  func.func @ssd_stream_tiles(%x: tensor<1x8xf32>,
                              %wg: tensor<8x16xf32>,
                              %wu: tensor<8x16xf32>,
                              %wd: tensor<16x8xf32>,
                              %w16: tensor<4194304xf32>,
                              %c16: tensor<4194304xf32>,
                              %c128: tensor<33554432xf32>) -> tensor<1x8xf32> {
    %obj = stor.object : !stor.object<tensor<4194304xf32>>
    %ssd = stor.materialize %obj : !stor.object<tensor<4194304xf32>> -> !stor.buffer<tensor<4194304xf32>, ssd>
    %hbm = stor.materialize %obj : !stor.object<tensor<4194304xf32>> -> !stor.buffer<tensor<4194304xf32>, hbm>
    stor.pack %w16 into %ssd : tensor<4194304xf32>, !stor.buffer<tensor<4194304xf32>, ssd>
    // Sequential SSD → Host. Not a concurrent candidate.
    %host = stor.transfer %ssd : !stor.buffer<tensor<4194304xf32>, ssd> -> !stor.buffer<tensor<4194304xf32>, host>
    // Candidate #0: Host→HBM || current compute tile.
    %y = sched.concurrent -> tensor<1x8xf32> {
      %ts = sched.task {
        %t = comm.stream %host, %hbm : !stor.buffer<tensor<4194304xf32>, host>, !stor.buffer<tensor<4194304xf32>, hbm> -> !sched.token
        sched.yield
      }
      %tc, %out = sched.task -> tensor<1x8xf32> {
        %mlp = comp.gated_mlp %x, %wg, %wu, %wd {activation = #comp.activation<silu>}
          : tensor<1x8xf32>, tensor<8x16xf32>, tensor<8x16xf32>, tensor<16x8xf32>
            -> tensor<1x8xf32>
        sched.yield %mlp : tensor<1x8xf32>
      }
      sched.yield %out : tensor<1x8xf32>
    }
    // Candidate #1: 16MiB compute siblings. Semantic concurrent only.
    sched.concurrent {
      %ta = sched.task {
        %a = comp.elemwise %c16 {kind = #comp.elemwise<silu>} : tensor<4194304xf32> -> tensor<4194304xf32>
        sched.yield
      }
      %tb = sched.task {
        %b = comp.elemwise %c16 {kind = #comp.elemwise<silu>} : tensor<4194304xf32> -> tensor<4194304xf32>
        sched.yield
      }
      sched.yield
    }
    // Candidate #2: 128MiB compute siblings. Semantic concurrent only.
    sched.concurrent {
      %tc0 = sched.task {
        %c = comp.elemwise %c128 {kind = #comp.elemwise<silu>} : tensor<33554432xf32> -> tensor<33554432xf32>
        sched.yield
      }
      %td = sched.task {
        %d = comp.elemwise %c128 {kind = #comp.elemwise<silu>} : tensor<33554432xf32> -> tensor<33554432xf32>
        sched.yield
      }
      sched.yield
    }
    return %y : tensor<1x8xf32>
  }
}
