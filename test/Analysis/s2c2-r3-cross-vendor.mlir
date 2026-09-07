// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-r3-contract | FileCheck %s --check-prefix=CONTRACT
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --query-cap 'C||C' --cap-catalog %S/../../docs/design/v3-dataset/ascend910b/cc-size-applicability.jsonl --n 4194304 | FileCheck %s --check-prefix=QOV-M
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --query-cap 'C||C' --cap-catalog %S/../../docs/design/v3-dataset/ascend910b/capability.jsonl --n 4194304 | FileCheck %s --check-prefix=Q69
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --query-cap 'C||C' --cap-catalog %S/../../docs/design/v3-dataset/ascend910b/cc-size-applicability.jsonl --n 33554432 | FileCheck %s --check-prefix=QOV-S
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --query-cap 'C||C' --cap-catalog %S/../../docs/design/v3-dataset/ascend910b/capability.jsonl --n 33554432 | FileCheck %s --check-prefix=Q69
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=rtx4090 profile=%S/../../docs/design/v3-dataset/v3-cap-schema-4090.jsonl" --check-s2c2-execution 2>&1 | grep capability-schedule | FileCheck %s --check-prefix=GPU-LOG
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=ascend910b:ascend profile=%S/../../docs/design/v3-dataset/ascend910b/cc-size-applicability.jsonl" --check-s2c2-execution 2>&1 | grep capability-schedule | FileCheck %s --check-prefix=OV-LOG
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=ascend910b:ascend profile=%S/../../docs/design/v3-dataset/ascend910b/capability.jsonl" --check-s2c2-execution 2>&1 | grep capability-schedule | FileCheck %s --check-prefix=CAT-LOG
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=rtx4090 profile=%S/../../docs/design/v3-dataset/v3-cap-schema-4090.jsonl" --check-s2c2-execution | FileCheck %s --check-prefix=GPU
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=ascend910b:ascend profile=%S/../../docs/design/v3-dataset/ascend910b/cc-size-applicability.jsonl" --check-s2c2-execution | FileCheck %s --check-prefix=OV
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=ascend910b:ascend profile=%S/../../docs/design/v3-dataset/ascend910b/capability.jsonl" --check-s2c2-execution | FileCheck %s --check-prefix=CAT

// PR-R3: same IR, 4090 vs 910B scoped evidence. C||C need not
// disagree. Insufficient evidence keeps concurrent. Not Cost.
// #69 stays underdetermined. Do not invent 910B C||C = parallel.

// CONTRACT: pr-r3 pair-contract=same
// CONTRACT: pr-r3 require-cc-disagree=no
// CONTRACT: pr-r3 insufficient=keep
// CONTRACT: pr-r3 guess=no
// CONTRACT: pr-r3 note catalog-untouched
// CONTRACT: pr-r3 cost=unchanged
// CONTRACT-NOT: Cost v0.4
// CONTRACT-NOT: password

// 16MiB overlay mixed band is not a rewrite license.
// QOV-M: "pair":"C||C"
// QOV-M: "pair_relation":"mixed"
// QOV-M: "phase_band":"mixed"
// QOV-M: "rewrite_license":false
// QOV-M-NOT: "pair_relation":"serial"

// #69 catalog stays underdetermined at both payloads.
// Q69: "pair":"C||C"
// Q69: "pair_relation":"underdetermined"
// Q69: "applicable":false
// Q69-NOT: "pair_relation":"serial"

// 128MiB overlay serial band is rewrite-licensed.
// QOV-S: "pair":"C||C"
// QOV-S-SAME: "pair_relation":"serial"
// QOV-S-SAME: "size_range":"128MiB..512MiB"
// QOV-S-SAME: "rewrite_license":true

// GPU-LOG: pair=C||C relation=serial
// GPU-LOG: rewrite_license=yes
// GPU-LOG: applicable=yes
// GPU-LOG: decision=serialize
// GPU-LOG: pair=C||C relation=serial
// GPU-LOG: decision=serialize
// GPU-LOG: cost=unchanged

// OV-LOG: pair=C||C relation=mixed
// OV-LOG: rewrite_license=no
// OV-LOG: decision=keep
// OV-LOG: pair=C||C relation=serial
// OV-LOG: rewrite_license=yes
// OV-LOG: applicable=yes
// OV-LOG: decision=serialize
// OV-LOG: cost=unchanged

// CAT-LOG: pair=C||C relation=underdetermined
// CAT-LOG: decision=keep
// CAT-LOG: pair=C||C relation=underdetermined
// CAT-LOG: decision=keep
// CAT-LOG-NOT: decision=serialize
// CAT-LOG: cost=unchanged

module {
  // 16MiB: 4090 serializes; 910B overlay keeps mixed; #69 keeps.
  // GPU-LABEL: func.func @cc_mixed_16mib
  // GPU: sched.task
  // GPU: comp.elemwise
  // GPU: sched.task
  // GPU: comp.elemwise
  // GPU-NOT: sched.concurrent
  // GPU-NOT: sched.wait
  // OV-LABEL: func.func @cc_mixed_16mib
  // OV: sched.concurrent
  // OV: comp.elemwise
  // CAT-LABEL: func.func @cc_mixed_16mib
  // CAT: sched.concurrent
  func.func @cc_mixed_16mib(%x: tensor<4194304xf32>) {
    sched.concurrent {
      %ta = sched.task {
        %y = comp.elemwise %x {kind = #comp.elemwise<silu>} : tensor<4194304xf32> -> tensor<4194304xf32>
        sched.yield
      }
      %tb = sched.task {
        %z = comp.elemwise %x {kind = #comp.elemwise<silu>} : tensor<4194304xf32> -> tensor<4194304xf32>
        sched.yield
      }
      sched.yield
    }
    return
  }

  // 128MiB: 4090 and overlay both serialize; #69 still keeps.
  // GPU-LABEL: func.func @cc_serial_128mib
  // GPU: sched.task
  // GPU: comp.elemwise
  // GPU-NOT: sched.concurrent
  // GPU-NOT: sched.wait
  // OV-LABEL: func.func @cc_serial_128mib
  // OV: sched.task
  // OV: comp.elemwise
  // OV: sched.task
  // OV: comp.elemwise
  // OV-NOT: sched.concurrent
  // OV-NOT: sched.wait
  // CAT-LABEL: func.func @cc_serial_128mib
  // CAT: sched.concurrent
  func.func @cc_serial_128mib(%x: tensor<33554432xf32>) {
    sched.concurrent {
      %ta = sched.task {
        %y = comp.elemwise %x {kind = #comp.elemwise<silu>} : tensor<33554432xf32> -> tensor<33554432xf32>
        sched.yield
      }
      %tb = sched.task {
        %z = comp.elemwise %x {kind = #comp.elemwise<silu>} : tensor<33554432xf32> -> tensor<33554432xf32>
        sched.yield
      }
      sched.yield
    }
    return
  }
}
