// RUN: s2c2-opt %S/storage-loop.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global-schedule|hierarchy-global-candidate|hierarchy-global-cost|hierarchy-global-measured' | FileCheck %s --check-prefix=F
// RUN: s2c2-opt %S/storage-loop.mlir --profile=910B --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global-schedule|hierarchy-global-cost-coincide' | FileCheck %s --check-prefix=NPU
// RUN: s2c2-opt %S/storage-loop.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1-ntile-4090.jsonl" --check-s2c2-execution 2>&1 | grep hierarchy-global-measured | FileCheck %s --check-prefix=NTILE
// RUN: s2c2-opt %S/storage-loop.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1-hierarchy-4090.jsonl" --check-s2c2-execution 2>&1 | grep hierarchy-global-measured | FileCheck %s --check-prefix=HIER
// RUN: s2c2-opt %S/storage-loop.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --s2c2-lower | FileCheck %s --check-prefix=LOWER

// Phase 5D design lock: existing F(@ssd_loop_pipeline) is
// product=4, enumerated, and structurally PREFETCH/PRESERVE ×
// loop-invariant KEEP/TRANSFER. cost-v04 still coincide with
// default-3g. Frozen 5B/5C tables stay not-measured here.
// Does not add a runtime. Does not rewrite. Does not FileCheck
// microseconds. #69 untouched.

// F: hierarchy-global-schedule chains=8 product=4 enumerated=yes truncated=no legal=4
// F: hierarchy-global-candidate actions=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH//TRANSFER//TRANSFER|KEEP_RESIDENCY|TRANSFER//MATERIALIZE
// F: hierarchy-global-candidate actions=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH//TRANSFER//TRANSFER|TRANSFER|TRANSFER//MATERIALIZE
// F: hierarchy-global-candidate actions=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PRESERVE//TRANSFER//TRANSFER|KEEP_RESIDENCY|TRANSFER//MATERIALIZE
// F: hierarchy-global-candidate actions=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PRESERVE//TRANSFER//TRANSFER|TRANSFER|TRANSFER//MATERIALIZE
// F: hierarchy-global-cost ranked=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH//TRANSFER//TRANSFER|KEEP_RESIDENCY|TRANSFER//MATERIALIZE
// F-SAME: score=2
// F-SAME: policy=cost-v04
// F: hierarchy-global-cost-coincide diverge=no
// F-SAME: note cost-v04-structural-frozen
// F: hierarchy-global-cost-candidate{{.*}}PREFETCH//TRANSFER//TRANSFER|KEEP_RESIDENCY|TRANSFER{{.*}}score=2
// F: hierarchy-global-cost-candidate{{.*}}PREFETCH//TRANSFER//TRANSFER|TRANSFER|TRANSFER{{.*}}score=3
// F: hierarchy-global-cost-candidate{{.*}}PRESERVE//TRANSFER//TRANSFER|KEEP_RESIDENCY|TRANSFER{{.*}}score=3
// F: hierarchy-global-cost-candidate{{.*}}PRESERVE//TRANSFER//TRANSFER|TRANSFER|TRANSFER{{.*}}score=4
// F: hierarchy-global-measured ranked=not-measured
// F-NOT: 10303
// F-NOT: 7463

// NPU: hierarchy-global-schedule{{.*}}product=4 enumerated=yes truncated=no legal=4
// NPU: hierarchy-global-cost-coincide diverge=no

// NTILE: hierarchy-global-measured ranked=not-measured
// NTILE: hierarchy-global-measured-diverge diverge=n/a

// HIER: hierarchy-global-measured ranked=not-measured
// HIER: hierarchy-global-measured-diverge diverge=n/a

// LOWER: scf.for
// LOWER: memref.copy
// LOWER-NOT: sched.wait
// LOWER-NOT: comm.stream

module {
}
