// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-ssd-mlp-wallclock-contract | FileCheck %s --check-prefix=CONTRACT
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-ssd-mlp-wallclock %S/../Pilot/ssd-mlp-wallclock-yes-fixture.log | FileCheck %s --check-prefix=YES
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-ssd-mlp-wallclock %S/../Pilot/ssd-mlp-wallclock-no-fixture.log | FileCheck %s --check-prefix=NO
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-ssd-mlp-wallclock %S/../../docs/design/v3-dataset/ssd-mlp-wallclock.log | FileCheck %s --check-prefix=HW
// RUN: s2c2-ascend-adapter --dry-run --ssd-mlp-wallclock 2>&1 | FileCheck %s --check-prefix=ASCEND
// RUN: s2c2-cuda-adapter --dry-run --ssd-mlp-wallclock 2>&1 | FileCheck %s --check-prefix=CUDA
// RUN: not s2c2-ascend-adapter --dry-run --ssd-mlp-wallclock --cc-rewrite 2>&1 | FileCheck %s --check-prefix=EXCL
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=rtx4090 profile=%S/../../docs/design/v3-dataset/v3-cap-schema-4090.jsonl" --check-s2c2-execution 2>&1 | grep capability-schedule | FileCheck %s --check-prefix=GPU-LOG
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=ascend910b:ascend profile=%S/../../docs/design/v3-dataset/ascend910b/cc-size-applicability.jsonl" --check-s2c2-execution 2>&1 | grep capability-schedule | FileCheck %s --check-prefix=OV-LOG
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=ascend910b:ascend profile=%S/../../docs/design/v3-dataset/ascend910b/capability.jsonl" --check-s2c2-execution 2>&1 | grep capability-schedule | FileCheck %s --check-prefix=CAT-LOG
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=rtx4090 profile=%S/../../docs/design/v3-dataset/v3-cap-schema-4090.jsonl" --check-s2c2-execution | FileCheck %s --check-prefix=GPU
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=ascend910b:ascend profile=%S/../../docs/design/v3-dataset/ascend910b/cc-size-applicability.jsonl" --check-s2c2-execution | FileCheck %s --check-prefix=OV
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=ascend910b:ascend profile=%S/../../docs/design/v3-dataset/ascend910b/capability.jsonl" --check-s2c2-execution | FileCheck %s --check-prefix=CAT
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=rtx4090 profile=%S/../../docs/design/v3-dataset/v3-cap-schema-4090.jsonl" --s2c2-lower | FileCheck %s --check-prefix=LOWER

// Complete SSD prefetch || Gated MLP plus licensed C||C at 128MiB.
// Program wall-clock is T_evi/T_seq, not the #76 stage A/B.
// No sibling wait. Not Cost. Do not FileCheck microseconds.

// CONTRACT: ssd-mlp-wallclock program-measurement=yes
// CONTRACT: no-evidence => no-destructive-optimization
// CONTRACT: invariant semantic-ne-perf-serial
// CONTRACT: invariant capability-ne-rewrite
// CONTRACT: invariant scoped-ne-global
// CONTRACT: invariant underdetermined-preserve
// CONTRACT: invariant rewrite-preserves-hb
// CONTRACT: note not-stage-ab
// CONTRACT: note t-base-is-t-seq
// CONTRACT: note t-opt-is-t-evi
// CONTRACT: note catalog-untouched
// CONTRACT: note logical-ssd-ne-disk
// CONTRACT: cost=unchanged
// CONTRACT-NOT: Cost v0.4
// CONTRACT-NOT: password

// YES: ssd-mlp-wallclock program-measurement=yes
// YES: ssd-mlp-wallclock measured=yes
// YES: ssd-mlp-wallclock t-opt-over-base-defined=yes
// YES: note t-base-is-t-seq
// YES: note t-opt-is-t-evi
// YES: note not-stage-ab
// YES: note 32M-outlier-not-cost
// YES: note catalog-untouched
// YES: cost=unchanged
// YES-NOT: Cost v0.4
// YES-NOT: password

// NO: ssd-mlp-wallclock measured=no
// NO: ssd-mlp-wallclock t-opt-over-base-defined=no
// NO: note not-stage-ab
// NO: cost=unchanged
// NO-NOT: Cost v0.4

// HW: ssd-mlp-wallclock program-measurement=yes
// HW: ssd-mlp-wallclock measured=yes
// HW: ssd-mlp-wallclock t-opt-over-base-defined=yes
// HW: note t-base-is-t-seq
// HW: note t-opt-is-t-evi
// HW: note catalog-untouched
// HW: cost=unchanged
// HW-NOT: note device-absent
// HW-NOT: Cost v0.4
// HW-NOT: password

// ASCEND: s2c2-ascend-adapter ssd-mlp-wallclock=1
// ASCEND: s2c2-ascend-adapter ssd-mlp-wallclock program-measurement=yes
// ASCEND: s2c2-ascend-adapter ssd-mlp-wallclock note not-stage-ab
// ASCEND: s2c2-ascend-adapter ssd-mlp-wallclock t-base=t-seq
// ASCEND: s2c2-ascend-adapter ssd-mlp-wallclock t-opt=t-evi
// ASCEND: s2c2-ascend-adapter ssd-mlp-wallclock n-htod=22528000
// ASCEND: s2c2-ascend-adapter ssd-mlp-wallclock n-cc=33554432
// ASCEND: s2c2-ascend-adapter ssd-mlp-wallclock note catalog-untouched
// ASCEND: s2c2-ascend-adapter ssd-mlp-wallclock note logical-ssd-ne-disk
// ASCEND: s2c2-ascend-adapter ssd-mlp-wallclock cost=unchanged
// ASCEND-NOT: Cost v0.4
// ASCEND-NOT: password

// CUDA: s2c2-cuda-adapter ssd-mlp-wallclock=1
// CUDA: s2c2-cuda-adapter ssd-mlp-wallclock program-measurement=yes
// CUDA: s2c2-cuda-adapter ssd-mlp-wallclock note not-stage-ab
// CUDA: s2c2-cuda-adapter ssd-mlp-wallclock t-base=t-seq
// CUDA: s2c2-cuda-adapter ssd-mlp-wallclock t-opt=t-evi
// CUDA: s2c2-cuda-adapter ssd-mlp-wallclock note catalog-untouched
// CUDA: s2c2-cuda-adapter ssd-mlp-wallclock note logical-ssd-ne-disk
// CUDA: s2c2-cuda-adapter ssd-mlp-wallclock cost=unchanged
// CUDA-NOT: Cost v0.4

// EXCL: cannot combine

// Prefetch || MLP stays concurrent. Licensed C||C serializes on
// 4090 and the 910B overlay; #69 keeps both stages.
// GPU-LOG: pair=C||HtoD
// GPU-LOG: decision=keep
// GPU-LOG: pair=C||C relation=serial
// GPU-LOG: decision=serialize
// GPU-LOG: cost=unchanged

// OV-LOG: pair=C||HtoD
// OV-LOG: decision=keep
// OV-LOG: pair=C||C relation=serial
// OV-LOG: rewrite_license=yes
// OV-LOG: decision=serialize
// OV-LOG: cost=unchanged

// CAT-LOG: pair=C||HtoD
// CAT-LOG: decision=keep
// CAT-LOG: pair=C||C relation=underdetermined
// CAT-LOG: decision=keep
// CAT-LOG-NOT: decision=serialize
// CAT-LOG: cost=unchanged

module {
  // GPU-LABEL: func.func @ssd_mlp_complete
  // OV-LABEL: func.func @ssd_mlp_complete
  // CAT-LABEL: func.func @ssd_mlp_complete
  // GPU: sched.concurrent
  // GPU: comm.stream
  // GPU: comp.gated_mlp
  // GPU: sched.task
  // GPU: comp.elemwise
  // GPU-NOT: sched.wait
  // OV: sched.concurrent
  // OV: comm.stream
  // OV: comp.gated_mlp
  // OV: sched.task
  // OV: comp.elemwise
  // OV-NOT: sched.wait
  // CAT: sched.concurrent
  // CAT: comm.stream
  // CAT: comp.gated_mlp
  // CAT: sched.concurrent
  // CAT: comp.elemwise
  // LOWER-LABEL: func.func @ssd_mlp_complete
  // LOWER: memref.copy
  // LOWER: linalg.matmul
  // LOWER-NOT: sched.concurrent
  // LOWER-NOT: comm.stream
  // LOWER-NOT: comp.gated_mlp
  func.func @ssd_mlp_complete(%x: tensor<1x4096xf16>,
                              %wg: tensor<4096x11008xf16>,
                              %wu: tensor<4096x11008xf16>,
                              %wd: tensor<11008x4096xf16>,
                              %next_w: tensor<11008x4096xf16>,
                              %ffn: tensor<33554432xf32>) -> tensor<1x4096xf16> {
    %obj = stor.object : !stor.object<tensor<11008x4096xf16>>
    %ssd = stor.materialize %obj : !stor.object<tensor<11008x4096xf16>> -> !stor.buffer<tensor<11008x4096xf16>, ssd>
    %hbm = stor.materialize %obj : !stor.object<tensor<11008x4096xf16>> -> !stor.buffer<tensor<11008x4096xf16>, hbm>
    stor.pack %next_w into %ssd : tensor<11008x4096xf16>, !stor.buffer<tensor<11008x4096xf16>, ssd>
    %y = sched.concurrent -> tensor<1x4096xf16> {
      %ts = sched.task {
        %t = comm.stream %ssd, %hbm : !stor.buffer<tensor<11008x4096xf16>, ssd>, !stor.buffer<tensor<11008x4096xf16>, hbm> -> !sched.token
        sched.yield
      }
      %tc, %out = sched.task -> tensor<1x4096xf16> {
        %mlp = comp.gated_mlp %x, %wg, %wu, %wd {activation = #comp.activation<silu>}
          : tensor<1x4096xf16>, tensor<4096x11008xf16>, tensor<4096x11008xf16>, tensor<11008x4096xf16>
            -> tensor<1x4096xf16>
        sched.yield %mlp : tensor<1x4096xf16>
      }
      sched.yield %out : tensor<1x4096xf16>
    }
    // 128MiB licensed C||C. 4090 / overlay serialize; #69 keeps.
    sched.concurrent {
      %ta = sched.task {
        %a = comp.elemwise %ffn {kind = #comp.elemwise<silu>} : tensor<33554432xf32> -> tensor<33554432xf32>
        sched.yield
      }
      %tb = sched.task {
        %b = comp.elemwise %ffn {kind = #comp.elemwise<silu>} : tensor<33554432xf32> -> tensor<33554432xf32>
        sched.yield
      }
      sched.yield
    }
    return %y : tensor<1x4096xf16>
  }
}
