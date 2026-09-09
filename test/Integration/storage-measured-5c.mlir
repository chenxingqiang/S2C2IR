// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-storage-measured-contract | FileCheck %s --check-prefix=CONTRACT
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --emit-storage-measured-from-ntile %S/storage-measured-5c.synth.log | grep -v '^{' | FileCheck %s --check-prefix=EMIT
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --emit-storage-measured-from-ntile %S/storage-measured-5c.synth.log | grep '^{' > %t.ntile.jsonl
// RUN: s2c2-opt %S/storage-ntile.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%t.ntile.jsonl" --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global-schedule|hierarchy-global-measured|hierarchy-global-cost-coincide' | FileCheck %s --check-prefix=RANK
// RUN: echo '{"schema":"s2c2.measured_storage_cost.v1","profile":"rtx4090","workload_class":"ssd-ntile-pipeline","candidate_signature":"NOT_IN_F","measured_time_us":1,"repetitions":5,"correctness":1,"source":"synthetic-test","measured":"yes","note":"must not expand F"}' >> %t.ntile.jsonl
// RUN: s2c2-opt %S/storage-ntile.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%t.ntile.jsonl" --check-s2c2-execution 2>&1 | grep hierarchy-global-measured | FileCheck %s --check-prefix=NOEXP
// RUN: s2c2-opt %S/storage-ntile.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1-hierarchy-4090.jsonl" --check-s2c2-execution 2>&1 | grep hierarchy-global-measured | FileCheck %s --check-prefix=HIER
// RUN: s2c2-opt %S/storage-ntile.mlir --s2c2-evidence-bounded-schedule="profile=910B measured-cost-table=%t.ntile.jsonl" --check-s2c2-execution 2>&1 | grep hierarchy-global-measured | FileCheck %s --check-prefix=CROSS
// RUN: s2c2-opt %S/storage-ntile.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep hierarchy-global-cost-coincide | FileCheck %s --check-prefix=COST
// RUN: s2c2-opt %S/storage-ntile.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%t.ntile.jsonl dump-schedule=%t.json" --check-s2c2-execution >/dev/null 2>&1
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-measured %t.json | FileCheck %s --check-prefix=AN
// RUN: s2c2-cuda-adapter --dry-run --storage-ntile-measured 2>&1 | FileCheck %s --check-prefix=CUDA
// RUN: s2c2-ascend-adapter --dry-run --storage-ntile-measured 2>&1 | FileCheck %s --check-prefix=ASCEND
// RUN: not s2c2-cuda-adapter --dry-run --storage-ntile-measured --storage-hierarchy-measured 2>&1 | FileCheck %s --check-prefix=EXCL
// RUN: echo 'storage-ntile-measured measured=yes' > %t.short.log
// RUN: echo 's2c2-cuda-run storage-ntile-measured signature=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER//PREFETCH|TRANSFER//TRANSFER|TRANSFER timing=1.0 correctness=1' >> %t.short.log
// RUN: echo 's2c2-cuda-run storage-ntile-measured signature=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER//PRESERVE|TRANSFER//TRANSFER|TRANSFER timing=2.0 correctness=1' >> %t.short.log
// RUN: echo 's2c2-cuda-run storage-ntile-measured signature=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PRESERVE|TRANSFER//PREFETCH|TRANSFER//TRANSFER|TRANSFER timing=3.0 correctness=1' >> %t.short.log
// RUN: not python3 %S/../../runtime/ascend/record_ascend.py --emit-storage-measured-from-ntile %t.short.log
// RUN: echo 'storage-ntile-measured measured=yes' > %t.dup.log
// RUN: echo 's2c2-cuda-run storage-ntile-measured signature=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER//PREFETCH|TRANSFER//TRANSFER|TRANSFER timing=1.0 correctness=1' >> %t.dup.log
// RUN: echo 's2c2-cuda-run storage-ntile-measured signature=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER//PREFETCH|TRANSFER//TRANSFER|TRANSFER timing=2.0 correctness=1' >> %t.dup.log
// RUN: echo 's2c2-cuda-run storage-ntile-measured signature=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER//PRESERVE|TRANSFER//TRANSFER|TRANSFER timing=3.0 correctness=1' >> %t.dup.log
// RUN: echo 's2c2-cuda-run storage-ntile-measured signature=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PRESERVE|TRANSFER//PREFETCH|TRANSFER//TRANSFER|TRANSFER timing=4.0 correctness=1' >> %t.dup.log
// RUN: echo 's2c2-cuda-run storage-ntile-measured signature=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PRESERVE|TRANSFER//PRESERVE|TRANSFER//TRANSFER|TRANSFER timing=5.0 correctness=1' >> %t.dup.log
// RUN: not python3 %S/../../runtime/ascend/record_ascend.py --emit-storage-measured-from-ntile %t.dup.log
// RUN: echo 'storage-ntile-measured measured=yes' > %t.extra.log
// RUN: echo 's2c2-cuda-run storage-ntile-measured signature=NOT_IN_F timing=1.0 correctness=1' >> %t.extra.log
// RUN: not python3 %S/../../runtime/ascend/record_ascend.py --emit-storage-measured-from-ntile %t.extra.log
// RUN: s2c2-opt %S/storage-ntile.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%t.ntile.jsonl" --s2c2-lower | FileCheck %s --check-prefix=LOWER

// Phase 5C: rank the existing 4-inhabitant F(@ssd_ntile_pipeline)
// under policy=measured-storage-v1. Synth log is a schema witness,
// not a device fact. diverge=no here because dummy S0 is fastest.
// Do not pre-claim copy-engine contention. cost-v04 stays FROZEN.
// Measurement cannot expand F. 4/4 required. Do not FileCheck
// microseconds. Does not rewrite. Does not re-measure 5A/5B.

// CONTRACT: note measurement-cannot-expand-F
// CONTRACT: note ntile-measured-this-cut
// CONTRACT: note two-independent-prefetch-sites
// CONTRACT: note contention-not-preclaimed
// CONTRACT: note diverge-yes-not-goal
// CONTRACT: cost=unchanged
// CONTRACT-NOT: password

// EMIT: storage-measured emit=device-log profile=rtx4090
// EMIT: storage-measured ntile-count=4
// EMIT: note one-row-per-signature
// EMIT: note two-independent-prefetch-sites
// EMIT: note contention-not-preclaimed
// EMIT: note not-hierarchy-8
// EMIT: note measured-ne-rewrite-license
// EMIT: cost=unchanged
// EMIT-NOT: password
// EMIT-NOT: 9000
// EMIT-NOT: 9300

// RANK: hierarchy-global-schedule chains=7 product=4 enumerated=yes truncated=no legal=4
// RANK: hierarchy-global-cost-coincide diverge=no
// RANK: hierarchy-global-measured ranked=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER//PREFETCH|TRANSFER//TRANSFER|TRANSFER
// RANK-SAME: policy=measured-storage-v1
// RANK-SAME: note measured-ne-rewrite-license
// RANK: hierarchy-global-measured-schedule enumerated=yes truncated=no
// RANK-SAME: ranked-eq-default-3g=yes
// RANK-SAME: measured-count=4
// RANK: hierarchy-global-measured-diverge diverge=no
// RANK-NOT: 9000
// RANK-NOT: 9300

// NOEXP: hierarchy-global-measured ranked=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER//PREFETCH|TRANSFER//TRANSFER|TRANSFER
// NOEXP: hierarchy-global-measured-schedule{{.*}}measured-count=4
// NOEXP-NOT: ranked=NOT_IN_F

// HIER: hierarchy-global-measured ranked=not-measured
// HIER: hierarchy-global-measured-diverge diverge=n/a

// CROSS: hierarchy-global-measured ranked=not-measured
// CROSS: hierarchy-global-measured-diverge diverge=n/a

// COST: hierarchy-global-cost-coincide diverge=no
// COST-SAME: note cost-v04-structural-frozen

// AN: storage-measured ranked=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER//PREFETCH|TRANSFER//TRANSFER|TRANSFER
// AN: storage-measured measured-count=4
// AN: storage-measured diverge=no
// AN: note measurement-cannot-expand-F
// AN: cost=unchanged
// AN-NOT: 9000

// CUDA: s2c2-cuda-adapter storage-ntile-measured=1
// CUDA: note one-arm-per-signature
// CUDA: note two-independent-prefetch-sites
// CUDA: note contention-not-preclaimed
// CUDA: note not-hierarchy-8
// CUDA: note measured-ne-rewrite-license
// CUDA: cost=unchanged

// ASCEND: s2c2-ascend-adapter storage-ntile-measured=1
// ASCEND: note two-independent-prefetch-sites
// ASCEND: note contention-not-preclaimed
// ASCEND: note not-hierarchy-8
// ASCEND: cost=unchanged

// EXCL: cannot combine

// LOWER: memref.copy
// LOWER-NOT: sched.wait
// LOWER-NOT: comm.stream

module {
}
