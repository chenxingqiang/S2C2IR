// RUN: s2c2-opt %s --s2c2-capability-query="device=ascend910b:ascend profile=%S/../../docs/design/v3-dataset/ascend910b/cc-size-applicability.jsonl producer=comp.silu consumer=comp.silu" 2>&1 | FileCheck %s --check-prefix=Q-CAT
// RUN: s2c2-opt %s --s2c2-capability-query="device=ascend910b:ascend profile=%S/../../docs/design/v3-dataset/ascend910b/cc-size-applicability.jsonl" 2>&1 | FileCheck %s --check-prefix=Q
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=ascend910b:ascend profile=%S/../../docs/design/v3-dataset/ascend910b/cc-size-applicability.jsonl" --check-s2c2-execution 2>&1 | grep capability-schedule | FileCheck %s --check-prefix=KEEP-LOG
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=ascend910b:ascend profile=%S/../../docs/design/v3-dataset/ascend910b/cc-size-applicability.jsonl" --check-s2c2-execution | FileCheck %s --check-prefix=KEEP
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=ascend910b:ascend profile=%S/../../docs/design/v3-dataset/ascend910b/capability.jsonl" --check-s2c2-execution 2>&1 | grep capability-schedule | FileCheck %s --check-prefix=CAT69
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=fixture:size-band profile=%S/size-band-licensed.jsonl" --check-s2c2-execution 2>&1 | grep capability-schedule | FileCheck %s --check-prefix=LIC-LOG
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=fixture:size-band profile=%S/size-band-licensed.jsonl" --check-s2c2-execution | FileCheck %s --check-prefix=LIC
// RUN: s2c2-opt %s --s2c2-capability-query="device=fixture:ambiguous profile=%S/size-band-ambiguous.jsonl producer=comp.silu consumer=comp.silu" 2>&1 | FileCheck %s --check-prefix=AMB-Q
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=fixture:ambiguous profile=%S/size-band-ambiguous.jsonl" --check-s2c2-execution 2>&1 | grep capability-schedule | FileCheck %s --check-prefix=AMB-LOG
// RUN: s2c2-opt %s --s2c2-capability-schedule="device=fixture:ambiguous profile=%S/size-band-ambiguous.jsonl" --check-s2c2-execution | FileCheck %s --check-prefix=AMB

// Size-banded C||C lookup. 910B overlay is queryable and does not
// serialize N>=32M. A fixture with rewrite_license=yes shows the
// future licensed path. Not Cost. Not PR-R3. #69 stays underdetermined.

// Catalog query has no payload: do not pick mixed or serial.
// Q-CAT: "applicable":"unknown"
// Q-CAT-SAME: "pair":"C||C"
// Q-CAT-SAME: "pair_relation":"underdetermined"
// Q-CAT-SAME: "rewrite_license":false
// Q-CAT-SAME: "size_range":"multiple"

// N=4M floats = 16MiB → mixed band. Evidence applies; no rewrite.
// Q: "applicable":true
// Q-SAME: "pair":"C||C"
// Q-SAME: "pair_relation":"mixed"
// Q-SAME: "phase_band":"mixed"
// Q-SAME: "rewrite_license":false
// Q-SAME: "size_range":"16MiB..48MiB"
// N=16M floats = 64MiB → transition band.
// Q: "pair":"C||C"
// Q-SAME: "pair_relation":"underdetermined"
// Q-SAME: "phase_band":"transition"
// Q-SAME: "rewrite_license":false
// Q-SAME: "size_range":"64MiB..127MiB"
// N=32M floats = 128MiB → serial evidence, rewrite_license=no.
// Q: "applicable":true
// Q-SAME: "pair":"C||C"
// Q-SAME: "pair_relation":"serial"
// Q-SAME: "phase_band":"serial"
// Q-SAME: "rewrite_license":false
// Q-SAME: "size_range":"128MiB..512MiB"

// KEEP-LOG: pair=C||C relation=mixed
// KEEP-LOG: rewrite_license=no
// KEEP-LOG: decision=keep
// KEEP-LOG: pair=C||C relation=underdetermined
// KEEP-LOG: decision=keep
// KEEP-LOG: pair=C||C relation=serial
// KEEP-LOG: rewrite_license=no
// KEEP-LOG: applicable=yes
// KEEP-LOG: decision=keep
// KEEP-LOG: cost=unchanged

// #69 catalog is still one underdetermined cell.
// CAT69: pair=C||C relation=underdetermined
// CAT69: decision=keep
// CAT69-NOT: decision=serialize

// Licensed fixture (not 910B): 16MiB serial band may flatten.
// LIC-LOG: pair=C||C relation=serial
// LIC-LOG: rewrite_license=yes
// LIC-LOG: applicable=yes
// LIC-LOG: decision=serialize
// Later functions are outside 16MiB..48MiB, so keep.
// LIC-LOG: decision=keep
// LIC-LOG: decision=keep

// Two unconstrained n/a cells for the same pair are ambiguous.
// Do not pick the serial rewrite_license=yes cell.
// AMB-Q: "applicable":"unknown"
// AMB-Q-SAME: "pair":"C||C"
// AMB-Q-SAME: "pair_relation":"underdetermined"
// AMB-Q-SAME: "rewrite_license":false
// AMB-Q-SAME: "size_range":"multiple"
// AMB-LOG: pair=C||C relation=underdetermined
// AMB-LOG: rewrite_license=no
// AMB-LOG: decision=keep
// AMB-LOG-NOT: decision=serialize

module {
  // KEEP-LABEL: func.func @cc_mixed_16mib
  // KEEP: sched.concurrent
  // KEEP: comp.elemwise
  // LIC-LABEL: func.func @cc_mixed_16mib
  // LIC: sched.task
  // LIC: comp.elemwise
  // LIC-NOT: sched.concurrent
  // AMB-LABEL: func.func @cc_mixed_16mib
  // AMB: sched.concurrent
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

  // KEEP-LABEL: func.func @cc_transition_64mib
  // KEEP: sched.concurrent
  // LIC-LABEL: func.func @cc_transition_64mib
  // LIC: sched.concurrent
  func.func @cc_transition_64mib(%x: tensor<16777216xf32>) {
    sched.concurrent {
      %ta = sched.task {
        %y = comp.elemwise %x {kind = #comp.elemwise<silu>} : tensor<16777216xf32> -> tensor<16777216xf32>
        sched.yield
      }
      %tb = sched.task {
        %z = comp.elemwise %x {kind = #comp.elemwise<silu>} : tensor<16777216xf32> -> tensor<16777216xf32>
        sched.yield
      }
      sched.yield
    }
    return
  }

  // KEEP-LABEL: func.func @cc_serial_128mib
  // KEEP: sched.concurrent
  // KEEP-NOT: sched.wait
  // LIC-LABEL: func.func @cc_serial_128mib
  // LIC: sched.concurrent
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
