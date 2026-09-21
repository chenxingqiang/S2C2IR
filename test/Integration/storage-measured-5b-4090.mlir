// RUN: python3 %S/../../runtime/ascend/record_ascend.py --emit-storage-measured-from-hierarchy %S/../../docs/design/v3-dataset/storage-measured-hierarchy-4090.log | grep -v '^{' | FileCheck %s --check-prefix=EMIT
// RUN: s2c2-opt %S/storage-hierarchy.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1-hierarchy-4090.jsonl" --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global-schedule|hierarchy-global-measured|hierarchy-global-cost-coincide' | FileCheck %s --check-prefix=DEV
// RUN: s2c2-opt %S/storage-hierarchy.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1.jsonl" --check-s2c2-execution 2>&1 | grep hierarchy-global-measured | FileCheck %s --check-prefix=FIXTURE
// RUN: s2c2-opt %S/storage-hierarchy.mlir --s2c2-evidence-bounded-schedule="profile=910B measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1-hierarchy-4090.jsonl" --check-s2c2-execution 2>&1 | grep hierarchy-global-measured | FileCheck %s --check-prefix=CROSS
// RUN: s2c2-opt %S/storage-hierarchy.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1-hierarchy-4090.jsonl dump-schedule=%t.json" --check-s2c2-execution >/dev/null 2>&1
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-measured %t.json | FileCheck %s --check-prefix=AN

// 4090 device-log fill of measured-storage-v1 on the 8-inhabitant
// hierarchy F. ArgMin is default-3g S0, so diverge=no. This is a
// valid 5B result. cost-v04 stays FROZEN. Do not FileCheck
// microseconds. Not a Capability cell. Does not rewrite the winner.
// Does not overwrite the frozen pipeline S0/S1 table. #69 untouched.

// EMIT: storage-measured emit=device-log profile=rtx4090
// EMIT: storage-measured hierarchy-count=8
// EMIT: note one-row-per-signature
// EMIT: note measurement-cannot-expand-F
// EMIT: note do-not-compare-4090-to-910B
// EMIT: note not-pipeline-s0-s1
// EMIT: cost=unchanged
// EMIT-NOT: password
// EMIT-NOT: 223.72
// EMIT-NOT: 5191
// EMIT-NOT: 7904

// DEV: hierarchy-global-schedule{{.*}}product=8 enumerated=yes truncated=no legal=8
// DEV: hierarchy-global-cost-coincide diverge=no
// DEV: hierarchy-global-measured ranked=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
// DEV-SAME: policy=measured-storage-v1
// DEV-SAME: note measured-yes-and-correctness
// DEV-SAME: note measured-ne-rewrite-license
// DEV-SAME: note cost-v04-structural-frozen
// DEV: hierarchy-global-measured-schedule enumerated=yes truncated=no
// DEV-SAME: ranked-eq-default-3g=yes
// DEV-SAME: measured-count=8
// DEV: hierarchy-global-measured-diverge diverge=no
// DEV-NOT: 5191
// DEV-NOT: 7904

// FIXTURE: hierarchy-global-measured ranked=not-measured
// FIXTURE: hierarchy-global-measured-diverge diverge=n/a

// CROSS: hierarchy-global-measured ranked=not-measured
// CROSS: hierarchy-global-measured-diverge diverge=n/a

// AN: storage-measured ranked=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
// AN: storage-measured ranked-eq-default-3g=yes
// AN: storage-measured measured-count=8
// AN: storage-measured diverge=no
// AN: storage-measured policy=measured-storage-v1
// AN: note measured-yes-and-correctness
// AN: cost=unchanged
// AN-NOT: password
// AN-NOT: 5191
// AN-NOT: 7904

module {
}
