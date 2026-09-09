// RUN: python3 %S/../../runtime/ascend/record_ascend.py --emit-storage-measured-from-loop %S/../../docs/design/v3-dataset/storage-measured-loop-910b.log | grep -v '^{' | FileCheck %s --check-prefix=EMIT
// RUN: s2c2-opt %S/storage-loop.mlir --s2c2-evidence-bounded-schedule="profile=910B measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1-loop-910b.jsonl" --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global-schedule|hierarchy-global-measured|hierarchy-global-cost-coincide' | FileCheck %s --check-prefix=DEV
// RUN: s2c2-opt %S/storage-loop.mlir --s2c2-evidence-bounded-schedule="profile=910B measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1.jsonl" --check-s2c2-execution 2>&1 | grep hierarchy-global-measured | FileCheck %s --check-prefix=FIXTURE
// RUN: s2c2-opt %S/storage-loop.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1-loop-910b.jsonl" --check-s2c2-execution 2>&1 | grep hierarchy-global-measured | FileCheck %s --check-prefix=CROSS
// RUN: s2c2-opt %S/storage-loop.mlir --s2c2-evidence-bounded-schedule="profile=910B measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1-loop-4090.jsonl" --check-s2c2-execution 2>&1 | grep hierarchy-global-measured | FileCheck %s --check-prefix=CROSS4090
// RUN: s2c2-opt %S/storage-loop.mlir --s2c2-evidence-bounded-schedule="profile=910B measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1-loop-910b.jsonl dump-schedule=%t.json" --check-s2c2-execution >/dev/null 2>&1
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-measured %t.json | FileCheck %s --check-prefix=AN

// 910B device-log fill of measured-storage-v1 on the 4-inhabitant
// loop F. ArgMin is default-3g S0 (PREFETCH+KEEP), so
// diverge=no. This is a valid 5D result. Do not pre-claim
// prefetch×KEEP contention. cost-v04 stays FROZEN. Do not
// FileCheck microseconds. Do not compare 4090 μs to 910B μs.
// Not a Capability cell. Does not rewrite the winner. Does
// not overwrite frozen 5A/5B/5C tables or 3J wall-clock.
// #69 untouched.

// EMIT: storage-measured emit=device-log profile=910B
// EMIT: storage-measured loop-count=4
// EMIT: note one-row-per-signature
// EMIT: note measurement-cannot-expand-F
// EMIT: note prefetch-keep-joint
// EMIT: note joint-not-preclaimed
// EMIT: note do-not-compare-4090-to-910B
// EMIT: note not-ntile-4
// EMIT: note not-3j-wallclock
// EMIT: cost=unchanged
// EMIT-NOT: password
// EMIT-NOT: 106.75
// EMIT-NOT: 6791
// EMIT-NOT: 11130

// DEV: hierarchy-global-schedule{{.*}}product=4 enumerated=yes truncated=no legal=4
// DEV: hierarchy-global-cost-coincide diverge=no
// DEV: hierarchy-global-measured ranked=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH//TRANSFER//TRANSFER|KEEP_RESIDENCY|TRANSFER//MATERIALIZE
// DEV-SAME: policy=measured-storage-v1
// DEV-SAME: note measured-yes-and-correctness
// DEV-SAME: note measured-ne-rewrite-license
// DEV-SAME: note cost-v04-structural-frozen
// DEV: hierarchy-global-measured-schedule enumerated=yes truncated=no
// DEV-SAME: ranked-eq-default-3g=yes
// DEV-SAME: measured-count=4
// DEV: hierarchy-global-measured-diverge diverge=no
// DEV-NOT: 6791
// DEV-NOT: 11130

// FIXTURE: hierarchy-global-measured ranked=not-measured
// FIXTURE: hierarchy-global-measured-diverge diverge=n/a

// CROSS: hierarchy-global-measured ranked=not-measured
// CROSS: hierarchy-global-measured-diverge diverge=n/a

// CROSS4090: hierarchy-global-measured ranked=not-measured
// CROSS4090: hierarchy-global-measured-diverge diverge=n/a

// AN: storage-measured ranked=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH//TRANSFER//TRANSFER|KEEP_RESIDENCY|TRANSFER//MATERIALIZE
// AN: storage-measured ranked-eq-default-3g=yes
// AN: storage-measured measured-count=4
// AN: storage-measured diverge=no
// AN: storage-measured policy=measured-storage-v1
// AN: note measured-yes-and-correctness
// AN: cost=unchanged
// AN-NOT: password
// AN-NOT: 6791
// AN-NOT: 11130

module {
}
