// RUN: python3 %S/../../runtime/ascend/record_ascend.py --emit-storage-measured-from-pipeline %S/../../docs/design/v3-dataset/storage-measured-910b.log | grep -v '^{' | FileCheck %s --check-prefix=EMIT
// RUN: s2c2-opt %S/storage-aware-pipeline.mlir --s2c2-evidence-bounded-schedule="profile=910B measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1-910b.jsonl" --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global-measured|hierarchy-global-cost-coincide' | FileCheck %s --check-prefix=DEV
// RUN: s2c2-opt %S/storage-aware-pipeline.mlir --s2c2-evidence-bounded-schedule="profile=910B measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1.jsonl" --check-s2c2-execution 2>&1 | grep hierarchy-global-measured | FileCheck %s --check-prefix=FIXTURE
// RUN: s2c2-opt %S/storage-aware-pipeline.mlir --s2c2-evidence-bounded-schedule="profile=910B measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1-4090.jsonl" --check-s2c2-execution 2>&1 | grep hierarchy-global-measured | FileCheck %s --check-prefix=CROSS
// RUN: s2c2-opt %S/storage-aware-pipeline.mlir --s2c2-evidence-bounded-schedule="profile=910B measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1-910b.jsonl dump-schedule=%t.json" --check-s2c2-execution >/dev/null 2>&1
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-measured %t.json | FileCheck %s --check-prefix=AN

// 910B device-log fill of measured-storage-v1. evi → S0 PREFETCH
// (default-3g). seq → S1 PRESERVE. On this log ArgMin is S0, so
// diverge=no. cost-v04 stays FROZEN. Do not FileCheck microseconds.
// Do not compare 4090 μs to 910B μs. Not a Capability cell.
// Does not rewrite the winner. #69 untouched.

// EMIT: storage-measured emit=device-log profile=910B
// EMIT: note measured-yes-and-correctness
// EMIT: note do-not-filecheck-microseconds
// EMIT: note do-not-compare-4090-to-910B
// EMIT: cost=unchanged
// EMIT-NOT: password
// EMIT-NOT: 106.75

// DEV: hierarchy-global-cost-coincide diverge=no
// DEV: hierarchy-global-measured ranked=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER
// DEV-SAME: policy=measured-storage-v1
// DEV-SAME: note measured-yes-and-correctness
// DEV-SAME: note measured-ne-rewrite-license
// DEV-SAME: note cost-v04-structural-frozen
// DEV: hierarchy-global-measured-schedule enumerated=yes truncated=no
// DEV-SAME: ranked-eq-default-3g=yes
// DEV-SAME: measured-count=2
// DEV: hierarchy-global-measured-diverge diverge=no
// DEV-NOT: 12720
// DEV-NOT: 13381

// FIXTURE: hierarchy-global-measured ranked=not-measured
// FIXTURE: hierarchy-global-measured-diverge diverge=n/a

// CROSS: hierarchy-global-measured ranked=not-measured
// CROSS: hierarchy-global-measured-diverge diverge=n/a

// AN: storage-measured ranked=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER
// AN: storage-measured ranked-eq-default-3g=yes
// AN: storage-measured diverge=no
// AN: storage-measured policy=measured-storage-v1
// AN: note measured-yes-and-correctness
// AN: cost=unchanged
// AN-NOT: password
// AN-NOT: 12720
// AN-NOT: 13381

module {
}
