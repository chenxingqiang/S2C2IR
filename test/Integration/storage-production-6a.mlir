// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-schedule-policy-contract | FileCheck %s --check-prefix=CONTRACT
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-storage-measured-contract | FileCheck %s --check-prefix=MEAS
// RUN: s2c2-opt %S/storage-aware-pipeline.mlir --profile=rtx4090 --schedule-policy=default-3g --check-s2c2-execution 2>&1 | grep -E 's2c2-schedule-policy|hierarchy-global selected|hierarchy-global-measured ranked' | FileCheck %s --check-prefix=API
// RUN: s2c2-opt %S/storage-aware-pipeline.mlir --profile=rtx4090 --s2c2-evidence-bounded-schedule="schedule-policy=cost-v04" --check-s2c2-execution 2>&1 | grep s2c2-schedule-policy | FileCheck %s --check-prefix=COST
// RUN: sed -e 's/"measured":"no"/"measured":"yes"/' -e 's/"source":"fixture-table"/"source":"synthetic-test"/' %S/../../docs/design/v3-dataset/storage-measured-v1.jsonl > %t.yes.jsonl
// RUN: s2c2-opt %S/storage-aware-pipeline.mlir --profile=rtx4090 --schedule-policy=measured-storage-v1 --measured-cost-table=%t.yes.jsonl --explain --check-s2c2-execution 2>&1 | grep -E 's2c2-schedule-policy|s2c2-schedule-explain|hierarchy-global selected' | FileCheck %s --check-prefix=MEASSEL
// RUN: s2c2-opt %S/storage-aware-pipeline.mlir --profile=rtx4090 --measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1.jsonl --schedule-policy=measured-storage-v1 --check-s2c2-execution 2>&1 | grep s2c2-schedule-policy | FileCheck %s --check-prefix=NO
// RUN: s2c2-opt %S/storage-aware-pipeline.mlir --profile=910B --schedule-policy=measured-storage-v1 --measured-cost-table=%t.yes.jsonl --check-s2c2-execution 2>&1 | grep s2c2-schedule-policy | FileCheck %s --check-prefix=CROSS
// RUN: s2c2-opt %S/storage-global.mlir --profile=rtx4090 --schedule-policy=measured-storage-v1 --explain --check-s2c2-execution 2>&1 | grep s2c2-schedule-explain | FileCheck %s --check-prefix=TRUNC
// RUN: echo '{"schema":"s2c2.measured_storage_cost.v1","profile":"rtx4090","workload_class":"storage-aware-pipeline","candidate_signature":"NOT_IN_F","measured_time_us":1,"repetitions":1,"correctness":1,"source":"synthetic-test","measured":"yes","note":"must not expand F"}' >> %t.yes.jsonl
// RUN: s2c2-opt %S/storage-aware-pipeline.mlir --profile=rtx4090 --schedule-policy=measured-storage-v1 --measured-cost-table=%t.yes.jsonl --check-s2c2-execution 2>&1 | grep -E 's2c2-schedule-policy|hierarchy-global-measured ranked' | FileCheck %s --check-prefix=NOEXP
// RUN: s2c2-opt %S/storage-aware-pipeline.mlir --profile=unknown --schedule-policy=default-3g --check-s2c2-execution 2>&1 | grep -E 's2c2-schedule-policy|capability-schedule' | FileCheck %s --check-prefix=UNK
// RUN: not s2c2-opt %S/storage-aware-pipeline.mlir --profile=rtx4090 --schedule-policy=invented --check-s2c2-execution 2>&1 | FileCheck %s --check-prefix=BAD
// RUN: s2c2-opt %S/storage-aware-pipeline.mlir --profile=rtx4090 --schedule-policy=measured-storage-v1 --measured-cost-table=%S/../../docs/design/v3-dataset/storage-measured-v1-4090.jsonl --s2c2-lower | FileCheck %s --check-prefix=LOWER

// Phase 6A production path: unified --schedule-policy + --explain.
// Policy selects among legal F members. It does not create
// legality and does not grant rewrite. 5A-5D stay frozen.
// 5E is not opened. Do not FileCheck microseconds.

// CONTRACT: schedule-policy compiler-driven=yes
// CONTRACT: policy default-3g|cost-v04|measured-storage-v1
// CONTRACT: note selection-ne-legality
// CONTRACT: note selection-ne-rewrite-license
// CONTRACT: note five-e-not-opened
// CONTRACT: note campaign-5a-5d-frozen
// CONTRACT: note compiler-ne-campaign-log
// CONTRACT: cost=unchanged
// CONTRACT-NOT: password

// MEAS: note schedule-policy-selection-only
// MEAS: note explain-ne-rewrite
// MEAS: note production-path-6a
// MEAS: cost=unchanged

// API: hierarchy-global selected={{.*}}PREFETCH{{.*}}policy=default-3g
// API: s2c2-schedule-policy name=default-3g{{.*}}applicable=yes{{.*}}rewrite=no
// API-SAME: note selection-ne-rewrite-license
// API-SAME: note five-e-not-opened
// API-NOT: password

// COST: s2c2-schedule-policy name=cost-v04{{.*}}source=cost-v04{{.*}}rewrite=no
// COST: s2c2-schedule-policy coincide-default-3g=yes reason=cost-v04-argmin rewrite=no

// MEASSEL: hierarchy-global selected={{.*}}PREFETCH{{.*}}policy=default-3g
// MEASSEL: s2c2-schedule-policy name=measured-storage-v1{{.*}}PRESERVE{{.*}}rewrite=no
// MEASSEL: s2c2-schedule-policy coincide-default-3g=no reason=measured-cost-argmin rewrite=no
// MEASSEL: s2c2-schedule-explain{{.*}}policy=measured-storage-v1
// MEASSEL: s2c2-schedule-explain{{.*}}evidence=yes time-us={{[0-9]+}}
// MEASSEL: s2c2-schedule-explain selected={{.*}}PRESERVE{{.*}}source=measured-storage-v1
// MEASSEL: s2c2-schedule-explain rewrite=no
// MEASSEL: s2c2-schedule-explain{{.*}}note selection-ne-rewrite-license
// MEASSEL-NOT: 8495
// MEASSEL-NOT: sched.wait

// NO: s2c2-schedule-policy name=measured-storage-v1{{.*}}applicable=no{{.*}}source=default-3g{{.*}}rewrite=no
// NO: s2c2-schedule-policy coincide-default-3g=yes reason=not-measured rewrite=no

// CROSS: s2c2-schedule-policy name=measured-storage-v1{{.*}}applicable=no{{.*}}rewrite=no
// CROSS: s2c2-schedule-policy{{.*}}reason=not-measured

// TRUNC: s2c2-schedule-explain ranking=not-enumerated
// TRUNC: s2c2-schedule-explain{{.*}}source=default-3g applicable=no
// TRUNC: s2c2-schedule-explain rewrite=no reason=not-enumerated

// NOEXP: hierarchy-global-measured ranked={{.*}}PRESERVE
// NOEXP: s2c2-schedule-policy name=measured-storage-v1{{.*}}PRESERVE{{.*}}rewrite=no
// NOEXP-NOT: ranked=NOT_IN_F

// UNK: capability-schedule{{.*}}decision=keep
// UNK: s2c2-schedule-policy name=default-3g{{.*}}rewrite=no
// UNK-NOT: rewrite=concurrent-to-serial

// BAD: unknown --schedule-policy=invented

// LOWER: memref.copy
// LOWER-NOT: sched.wait
// LOWER-NOT: comm.stream

module {
}
