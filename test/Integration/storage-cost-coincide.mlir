// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-storage-cost-contract | FileCheck %s --check-prefix=CONTRACT
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep hierarchy-global-cost-coincide | FileCheck %s --check-prefix=HIER-4090
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=unknown --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep hierarchy-global-cost-coincide | FileCheck %s --check-prefix=HIER-UNK
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=910B --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep hierarchy-global-cost-coincide | FileCheck %s --check-prefix=HIER-910B
// RUN: s2c2-opt %S/storage-ntile.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep hierarchy-global-cost-coincide | FileCheck %s --check-prefix=NTILE
// RUN: s2c2-opt %S/storage-loop.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep hierarchy-global-cost-coincide | FileCheck %s --check-prefix=LOOP
// RUN: s2c2-opt %S/storage-aware-pipeline.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep hierarchy-global-cost-coincide | FileCheck %s --check-prefix=PIPE
// RUN: s2c2-opt %S/storage-joint.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep hierarchy-global-cost-coincide | FileCheck %s --check-prefix=JOINT
// RUN: s2c2-opt %S/storage-global.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep hierarchy-global-cost-coincide | FileCheck %s --check-prefix=TRUNC
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2> %t.gpu.err
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-cost %t.gpu.err | FileCheck %s --check-prefix=AN

// Witness: under current structural ticks, cost-v04 ArgMin is the
// default-3g inhabitant on every enumerated Storage fixture.
// Truncated F is not ranked. This is not wall-clock and not a new
// Cost dimension. Do not FileCheck microseconds.

// CONTRACT: note policy=cost-v04
// CONTRACT: note default-3g-frozen
// CONTRACT: note structural-ticks-not-wallclock
// CONTRACT: note runtime-correlation-not-applicable
// CONTRACT: cost=unchanged

// HIER-4090: hierarchy-global-cost-coincide diverge=no
// HIER-4090-SAME: note structural-ticks-not-wallclock
// HIER-4090-SAME: note runtime-correlation-not-applicable

// HIER-UNK: hierarchy-global-cost-coincide diverge=no
// HIER-910B: hierarchy-global-cost-coincide diverge=no
// NTILE: hierarchy-global-cost-coincide diverge=no
// LOOP: hierarchy-global-cost-coincide diverge=no
// PIPE: hierarchy-global-cost-coincide diverge=no
// JOINT: hierarchy-global-cost-coincide diverge=no

// TRUNC: hierarchy-global-cost-coincide diverge=n/a
// TRUNC-SAME: note cost-does-not-rank-truncated-F
// TRUNC-SAME: note runtime-correlation-not-applicable

// AN: storage-cost ranked-eq-default-3g=yes
// AN: storage-cost diverge=no
// AN: note structural-ticks-not-wallclock
// AN: note runtime-correlation-not-applicable
// AN-NOT: Cost v0.4

module {
}
