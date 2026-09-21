// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-storage-measured-contract | FileCheck %s --check-prefix=CONTRACT
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --emit-storage-measured-from-hierarchy %S/storage-measured-5b.synth.log | grep -v '^{' | FileCheck %s --check-prefix=EMIT
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --emit-storage-measured-from-hierarchy %S/storage-measured-5b.synth.log | grep '^{' > %t.hier.jsonl
// RUN: s2c2-opt %S/storage-hierarchy.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%t.hier.jsonl" --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global-schedule|hierarchy-global-measured|hierarchy-global-cost-coincide' | FileCheck %s --check-prefix=RANK
// RUN: echo '{"schema":"s2c2.measured_storage_cost.v1","profile":"rtx4090","workload_class":"ssd-hierarchy-lifetime","candidate_signature":"NOT_IN_F","measured_time_us":1,"repetitions":5,"correctness":1,"source":"synthetic-test","measured":"yes","note":"must not expand F"}' >> %t.hier.jsonl
// RUN: s2c2-opt %S/storage-hierarchy.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%t.hier.jsonl" --check-s2c2-execution 2>&1 | grep hierarchy-global-measured | FileCheck %s --check-prefix=NOEXP
// RUN: s2c2-opt %S/storage-hierarchy.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1.jsonl" --check-s2c2-execution 2>&1 | grep hierarchy-global-measured | FileCheck %s --check-prefix=FIXTURE
// RUN: s2c2-opt %S/storage-hierarchy.mlir --s2c2-evidence-bounded-schedule="profile=910B measured-cost-table=%t.hier.jsonl" --check-s2c2-execution 2>&1 | grep hierarchy-global-measured | FileCheck %s --check-prefix=CROSS
// RUN: s2c2-opt %S/storage-hierarchy.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep hierarchy-global-cost-coincide | FileCheck %s --check-prefix=COST
// RUN: s2c2-opt %S/storage-hierarchy.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%t.hier.jsonl dump-schedule=%t.json" --check-s2c2-execution >/dev/null 2>&1
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-measured %t.json | FileCheck %s --check-prefix=AN
// RUN: s2c2-cuda-adapter --dry-run --storage-hierarchy-measured 2>&1 | FileCheck %s --check-prefix=CUDA
// RUN: s2c2-ascend-adapter --dry-run --storage-hierarchy-measured 2>&1 | FileCheck %s --check-prefix=ASCEND
// RUN: not s2c2-cuda-adapter --dry-run --storage-hierarchy-measured --storage-measured 2>&1 | FileCheck %s --check-prefix=EXCL
// RUN: echo 'storage-hierarchy-measured measured=yes' > %t.short.log
// RUN: echo 's2c2-cuda-run storage-hierarchy-measured signature=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY timing=1.0 correctness=1' >> %t.short.log
// RUN: echo 's2c2-cuda-run storage-hierarchy-measured signature=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER|KEEP_RESIDENCY|TRANSFER timing=2.0 correctness=1' >> %t.short.log
// RUN: not python3 %S/../../runtime/ascend/record_ascend.py --emit-storage-measured-from-hierarchy %t.short.log
// RUN: echo 'storage-hierarchy-measured measured=yes' > %t.dup.log
// RUN: echo 's2c2-cuda-run storage-hierarchy-measured signature=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY timing=1.0 correctness=1' >> %t.dup.log
// RUN: echo 's2c2-cuda-run storage-hierarchy-measured signature=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY timing=2.0 correctness=1' >> %t.dup.log
// RUN: echo 's2c2-cuda-run storage-hierarchy-measured signature=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER|KEEP_RESIDENCY|TRANSFER timing=3.0 correctness=1' >> %t.dup.log
// RUN: not python3 %S/../../runtime/ascend/record_ascend.py --emit-storage-measured-from-hierarchy %t.dup.log
// RUN: echo 'storage-hierarchy-measured measured=yes' > %t.extra.log
// RUN: echo 's2c2-cuda-run storage-hierarchy-measured signature=NOT_IN_F timing=1.0 correctness=1' >> %t.extra.log
// RUN: not python3 %S/../../runtime/ascend/record_ascend.py --emit-storage-measured-from-hierarchy %t.extra.log
// RUN: s2c2-opt %S/storage-hierarchy.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%t.hier.jsonl" --s2c2-lower | FileCheck %s --check-prefix=LOWER

// Phase 5B: rank the existing 8-inhabitant F(@ssd_hierarchy_lifetime)
// under policy=measured-storage-v1. The synth log is a schema
// witness, not a device fact. diverge=no here because S0 is the
// dummy ArgMin; a later device table may still report diverge=yes
// or diverge=no. cost-v04 stays FROZEN. Measurement cannot expand
// F. One campaign row per signature. Do not FileCheck microseconds.
// Does not rewrite the winner. #69 untouched.

// CONTRACT: storage-measured compiler-driven=yes
// CONTRACT: note measured-yes-and-correctness
// CONTRACT: note measured-ne-rewrite-license
// CONTRACT: note cost-v04-structural-frozen
// CONTRACT: note one-row-per-signature
// CONTRACT: note measurement-cannot-expand-F
// CONTRACT: note measured-last-wins-duplicate-policy
// CONTRACT: note hierarchy-measured-this-cut
// CONTRACT: note pipeline-s0-s1-frozen
// CONTRACT: note diverge-yes-not-goal
// CONTRACT: cost=unchanged
// CONTRACT-NOT: password

// EMIT: storage-measured emit=device-log profile=rtx4090
// EMIT: storage-measured hierarchy-count=8
// EMIT: storage-measured note one-row-per-signature
// EMIT: storage-measured note measurement-cannot-expand-F
// EMIT: storage-measured note not-pipeline-s0-s1
// EMIT: storage-measured note measured-ne-rewrite-license
// EMIT: cost=unchanged
// EMIT-NOT: password
// EMIT-NOT: 8000
// EMIT-NOT: 8700

// RANK: hierarchy-global-schedule chains=4 product=8 enumerated=yes truncated=no legal=8
// RANK: hierarchy-global-cost-coincide diverge=no
// RANK: hierarchy-global-measured ranked=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
// RANK-SAME: policy=measured-storage-v1
// RANK-SAME: note measured-yes-and-correctness
// RANK-SAME: note measured-ne-rewrite-license
// RANK-SAME: note measured-last-wins-duplicate-policy
// RANK: hierarchy-global-measured-schedule enumerated=yes truncated=no
// RANK-SAME: ranked-eq-default-3g=yes
// RANK-SAME: measured-count=8
// RANK: hierarchy-global-measured-diverge diverge=no
// RANK-NOT: 8000
// RANK-NOT: 8700

// NOEXP: hierarchy-global-measured ranked=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
// NOEXP: hierarchy-global-measured-schedule{{.*}}measured-count=8
// NOEXP-NOT: ranked=NOT_IN_F

// FIXTURE: hierarchy-global-measured ranked=not-measured
// FIXTURE: hierarchy-global-measured-diverge diverge=n/a

// CROSS: hierarchy-global-measured ranked=not-measured
// CROSS: hierarchy-global-measured-diverge diverge=n/a

// COST: hierarchy-global-cost-coincide diverge=no
// COST-SAME: note cost-v04-structural-frozen

// AN: storage-measured ranked=MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER|KEEP_RESIDENCY|KEEP_RESIDENCY
// AN: storage-measured enumerated=yes
// AN: storage-measured ranked-eq-default-3g=yes
// AN: storage-measured measured-count=8
// AN: storage-measured diverge=no
// AN: storage-measured policy=measured-storage-v1
// AN: note one-row-per-signature
// AN: note measurement-cannot-expand-F
// AN: cost=unchanged
// AN-NOT: 8000

// CUDA: s2c2-cuda-adapter storage-hierarchy-measured=1
// CUDA: s2c2-cuda-adapter storage-hierarchy-measured note one-arm-per-signature
// CUDA: s2c2-cuda-adapter storage-hierarchy-measured note measurement-cannot-expand-F
// CUDA: s2c2-cuda-adapter storage-hierarchy-measured note keep-residency-ne-rewrite
// CUDA: s2c2-cuda-adapter storage-hierarchy-measured note not-pipeline-s0-s1
// CUDA: s2c2-cuda-adapter storage-hierarchy-measured note measured-ne-rewrite-license
// CUDA: s2c2-cuda-adapter storage-hierarchy-measured cost=unchanged

// ASCEND: s2c2-ascend-adapter storage-hierarchy-measured=1
// ASCEND: s2c2-ascend-adapter storage-hierarchy-measured note one-arm-per-signature
// ASCEND: s2c2-ascend-adapter storage-hierarchy-measured note measurement-cannot-expand-F
// ASCEND: s2c2-ascend-adapter storage-hierarchy-measured note keep-residency-ne-rewrite
// ASCEND: s2c2-ascend-adapter storage-hierarchy-measured note not-pipeline-s0-s1
// ASCEND: s2c2-ascend-adapter storage-hierarchy-measured cost=unchanged

// EXCL: cannot combine

// LOWER: memref.copy
// LOWER-NOT: sched.wait
// LOWER-NOT: comm.stream

module {
}
