// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-storage-measured-contract | FileCheck %s --check-prefix=CONTRACT
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --emit-storage-measured-from-loop %S/storage-measured-5d.synth.log | grep -v '^{' | FileCheck %s --check-prefix=EMIT
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --emit-storage-measured-from-loop %S/storage-measured-5d.synth.log | grep '^{' > %t.loop.jsonl
// RUN: s2c2-opt %S/storage-loop.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%t.loop.jsonl" --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global-schedule|hierarchy-global-measured|hierarchy-global-cost-coincide' | FileCheck %s --check-prefix=RANK
// RUN: echo '{"schema":"s2c2.measured_storage_cost.v1","profile":"rtx4090","workload_class":"ssd-loop-pipeline","candidate_signature":"NOT_IN_F","measured_time_us":1,"repetitions":5,"correctness":1,"source":"synthetic-test","measured":"yes","note":"must not expand F"}' >> %t.loop.jsonl
// RUN: s2c2-opt %S/storage-loop.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%t.loop.jsonl" --check-s2c2-execution 2>&1 | grep hierarchy-global-measured | FileCheck %s --check-prefix=NOEXP
// RUN: s2c2-opt %S/storage-loop.mlir --s2c2-evidence-bounded-schedule="profile=910B measured-cost-table=%t.loop.jsonl" --check-s2c2-execution 2>&1 | grep hierarchy-global-measured | FileCheck %s --check-prefix=CROSS
// RUN: s2c2-opt %S/storage-loop.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%t.loop.jsonl dump-schedule=%t.json" --check-s2c2-execution >/dev/null 2>&1
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-measured %t.json | FileCheck %s --check-prefix=AN
// RUN: s2c2-cuda-adapter --dry-run --storage-loop-measured 2>&1 | FileCheck %s --check-prefix=CUDA
// RUN: s2c2-ascend-adapter --dry-run --storage-loop-measured 2>&1 | FileCheck %s --check-prefix=ASCEND
// RUN: not s2c2-cuda-adapter --dry-run --storage-loop-measured --storage-ntile-measured 2>&1 | FileCheck %s --check-prefix=EXCL
// RUN: echo 'storage-loop-measured measured=yes' > %t.short.log
// RUN: echo 's2c2-cuda-run storage-loop-measured signature=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH//TRANSFER//TRANSFER|KEEP_RESIDENCY|TRANSFER//MATERIALIZE timing=1.0 correctness=1' >> %t.short.log
// RUN: echo 's2c2-cuda-run storage-loop-measured signature=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH//TRANSFER//TRANSFER|TRANSFER|TRANSFER//MATERIALIZE timing=2.0 correctness=1' >> %t.short.log
// RUN: echo 's2c2-cuda-run storage-loop-measured signature=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PRESERVE//TRANSFER//TRANSFER|KEEP_RESIDENCY|TRANSFER//MATERIALIZE timing=3.0 correctness=1' >> %t.short.log
// RUN: not python3 %S/../../runtime/ascend/record_ascend.py --emit-storage-measured-from-loop %t.short.log
// RUN: echo 'storage-loop-measured measured=yes' > %t.dup.log
// RUN: echo 's2c2-cuda-run storage-loop-measured signature=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH//TRANSFER//TRANSFER|KEEP_RESIDENCY|TRANSFER//MATERIALIZE timing=1.0 correctness=1' >> %t.dup.log
// RUN: echo 's2c2-cuda-run storage-loop-measured signature=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH//TRANSFER//TRANSFER|KEEP_RESIDENCY|TRANSFER//MATERIALIZE timing=2.0 correctness=1' >> %t.dup.log
// RUN: echo 's2c2-cuda-run storage-loop-measured signature=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH//TRANSFER//TRANSFER|TRANSFER|TRANSFER//MATERIALIZE timing=3.0 correctness=1' >> %t.dup.log
// RUN: echo 's2c2-cuda-run storage-loop-measured signature=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PRESERVE//TRANSFER//TRANSFER|KEEP_RESIDENCY|TRANSFER//MATERIALIZE timing=4.0 correctness=1' >> %t.dup.log
// RUN: echo 's2c2-cuda-run storage-loop-measured signature=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PRESERVE//TRANSFER//TRANSFER|TRANSFER|TRANSFER//MATERIALIZE timing=5.0 correctness=1' >> %t.dup.log
// RUN: not python3 %S/../../runtime/ascend/record_ascend.py --emit-storage-measured-from-loop %t.dup.log
// RUN: echo 'storage-loop-measured measured=yes' > %t.extra.log
// RUN: echo 's2c2-cuda-run storage-loop-measured signature=NOT_IN_F timing=1.0 correctness=1' >> %t.extra.log
// RUN: not python3 %S/../../runtime/ascend/record_ascend.py --emit-storage-measured-from-loop %t.extra.log
// RUN: s2c2-opt %S/storage-loop.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global-schedule|hierarchy-global-candidate|hierarchy-global-cost|hierarchy-global-measured' | FileCheck %s --check-prefix=F
// RUN: s2c2-opt %S/storage-loop.mlir --profile=910B --s2c2-evidence-bounded-schedule --check-s2c2-execution 2>&1 | grep -E 'hierarchy-global-schedule|hierarchy-global-cost-coincide' | FileCheck %s --check-prefix=NPU
// RUN: s2c2-opt %S/storage-loop.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1-ntile-4090.jsonl" --check-s2c2-execution 2>&1 | grep hierarchy-global-measured | FileCheck %s --check-prefix=NTILE
// RUN: s2c2-opt %S/storage-loop.mlir --s2c2-evidence-bounded-schedule="profile=rtx4090 measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1-hierarchy-4090.jsonl" --check-s2c2-execution 2>&1 | grep hierarchy-global-measured | FileCheck %s --check-prefix=HIER
// RUN: s2c2-opt %S/storage-loop.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule --s2c2-lower | FileCheck %s --check-prefix=LOWER

// Phase 5D: rank the existing 4-inhabitant F(@ssd_loop_pipeline)
// under policy=measured-storage-v1. Synth log is a schema witness,
// not a device fact. diverge=no here because dummy S0 is fastest.
// Do not pre-claim the prefetch×KEEP joint. cost-v04 stays FROZEN.
// Measurement cannot expand F. 4/4 required. Do not FileCheck
// microseconds. Does not rewrite. Does not re-measure 5A/5B/5C.
// Does not overwrite 3J wall-clock.

// CONTRACT: note measurement-cannot-expand-F
// CONTRACT: note loop-measured-this-cut
// CONTRACT: note prefetch-keep-joint
// CONTRACT: note joint-not-preclaimed
// CONTRACT: note diverge-yes-not-goal
// CONTRACT: cost=unchanged
// CONTRACT-NOT: password

// EMIT: storage-measured emit=device-log profile=rtx4090
// EMIT: storage-measured loop-count=4
// EMIT: note one-row-per-signature
// EMIT: note prefetch-keep-joint
// EMIT: note joint-not-preclaimed
// EMIT: note not-ntile-4
// EMIT: note not-3j-wallclock
// EMIT: cost=unchanged
// EMIT-NOT: password
// EMIT-NOT: 8000
// EMIT-NOT: 8300

// RANK: hierarchy-global-schedule chains=8 product=4 enumerated=yes truncated=no legal=4
// RANK: hierarchy-global-cost-coincide diverge=no
// RANK: hierarchy-global-measured ranked=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH//TRANSFER//TRANSFER|KEEP_RESIDENCY|TRANSFER//MATERIALIZE
// RANK-SAME: policy=measured-storage-v1
// RANK-SAME: note measured-ne-rewrite-license
// RANK: hierarchy-global-measured-schedule enumerated=yes truncated=no
// RANK-SAME: ranked-eq-default-3g=yes
// RANK-SAME: measured-count=4
// RANK: hierarchy-global-measured-diverge diverge=no
// RANK-NOT: 8000
// RANK-NOT: 8300

// NOEXP: hierarchy-global-measured ranked=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH//TRANSFER//TRANSFER|KEEP_RESIDENCY|TRANSFER//MATERIALIZE
// NOEXP: hierarchy-global-measured-schedule{{.*}}measured-count=4
// NOEXP-NOT: ranked=NOT_IN_F

// CROSS: hierarchy-global-measured ranked=not-measured
// CROSS: hierarchy-global-measured-diverge diverge=n/a

// AN: storage-measured ranked=MATERIALIZE//MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH//TRANSFER//TRANSFER|KEEP_RESIDENCY|TRANSFER//MATERIALIZE
// AN: storage-measured measured-count=4
// AN: storage-measured diverge=no
// AN: note measurement-cannot-expand-F
// AN: cost=unchanged
// AN-NOT: 8000

// CUDA: s2c2-cuda-adapter storage-loop-measured=1
// CUDA: note one-arm-per-signature
// CUDA: note prefetch-keep-joint
// CUDA: note joint-not-preclaimed
// CUDA: note not-ntile-4
// CUDA: note measured-ne-rewrite-license
// CUDA: cost=unchanged

// ASCEND: s2c2-ascend-adapter storage-loop-measured=1
// ASCEND: note prefetch-keep-joint
// ASCEND: note joint-not-preclaimed
// ASCEND: note not-ntile-4
// ASCEND: cost=unchanged

// EXCL: cannot combine

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
