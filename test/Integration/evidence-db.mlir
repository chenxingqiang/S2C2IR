// RUN: python3 %S/../../runtime/record_evidence.py --print-evidence-db-contract | FileCheck %s --check-prefix=CONTRACT
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-schedule-policy-contract | FileCheck %s --check-prefix=POL
// RUN: python3 %S/../../runtime/record_evidence.py --check-evidence-db | FileCheck %s --check-prefix=DB
// RUN: python3 %S/../../runtime/record_evidence.py --ingest-frozen-campaign --db %t.roundtrip.jsonl | FileCheck %s --check-prefix=INGEST
// RUN: diff %S/../../docs/design/v3-dataset/evidence-db.jsonl %t.roundtrip.jsonl
// RUN: python3 %S/../../runtime/record_evidence.py --ingest-measured-v1 %S/../../docs/design/v3-dataset/storage-measured-v1.jsonl --db %t.fix.jsonl --measurement-revision=fixture-v1 | FileCheck %s --check-prefix=FIXING
// RUN: python3 %S/../../runtime/record_evidence.py --query-evidence --db %t.fix.jsonl --profile=rtx4090 --workload-signature=storage-aware-pipeline --measurement-revision=fixture-v1 | FileCheck %s --check-prefix=FIXTURE
// RUN: python3 %S/../../runtime/record_evidence.py --export-measured-v1 --db %t.fix.jsonl --profile=rtx4090 --workload-signature=storage-aware-pipeline --measurement-revision=fixture-v1 --out %t.fix.v1.jsonl | FileCheck %s --check-prefix=FIXEXP
// RUN: python3 %S/../../runtime/record_evidence.py --export-measured-v1 --db %S/../../docs/design/v3-dataset/evidence-db.jsonl --profile=rtx4090 --workload-signature=storage-aware-pipeline --measurement-revision=5a-pipeline-4090 --out %t.a4090.jsonl | FileCheck %s --check-prefix=EXP5A
// RUN: s2c2-opt %S/storage-aware-pipeline.mlir --profile=rtx4090 --schedule-policy=measured-storage-v1 --measured-cost-table=%t.a4090.jsonl --check-s2c2-execution 2>&1 | grep -E 's2c2-schedule-policy|hierarchy-global-measured-diverge|hierarchy-global-measured-schedule' | FileCheck %s --check-prefix=RANK
// RUN: python3 %S/../../runtime/record_evidence.py --query-evidence --db %S/../../docs/design/v3-dataset/evidence-db.jsonl --profile=rtx4090 --workload-signature=ssd-loop-pipeline --measurement-revision=5d-loop-4090 | FileCheck %s --check-prefix=Q5D
// RUN: python3 %S/../../runtime/record_evidence.py --query-evidence --db %S/../../docs/design/v3-dataset/evidence-db.jsonl --profile=rtx4090 --workload-signature=ssd-loop-pipeline --measurement-revision=does-not-exist | FileCheck %s --check-prefix=ABSENT
// RUN: echo '{"schema":"s2c2.measured_storage_cost.v1","profile":"rtx4090","workload_class":"storage-aware-pipeline","candidate_signature":"MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER","measured_time_us":1,"repetitions":1,"correctness":1,"source":"device-log","measured":"pending","note":"pending is not ranking"}' > %t.pending.jsonl
// RUN: echo '{"schema":"s2c2.measured_storage_cost.v1","profile":"rtx4090","workload_class":"storage-aware-pipeline","candidate_signature":"MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PRESERVE|TRANSFER","measured_time_us":2,"repetitions":1,"correctness":1,"source":"device-log","measured":"pending","note":"pending is not ranking"}' >> %t.pending.jsonl
// RUN: python3 %S/../../runtime/record_evidence.py --ingest-measured-v1 %t.pending.jsonl --db %t.st.jsonl --measurement-revision=status-pending
// RUN: python3 %S/../../runtime/record_evidence.py --query-evidence --db %t.st.jsonl --measurement-revision=status-pending | FileCheck %s --check-prefix=PENDING
// RUN: python3 %S/../../runtime/record_evidence.py --export-measured-v1 --db %t.st.jsonl --measurement-revision=status-pending --out %t.pending.v1.jsonl | FileCheck %s --check-prefix=NOEXP
// RUN: echo '{"schema":"s2c2.measured_storage_cost.v1","profile":"rtx4090","workload_class":"storage-aware-pipeline","candidate_signature":"MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER","measured_time_us":1,"repetitions":1,"correctness":1,"source":"device-log","measured":"inferred","note":"inferred is not ranking"}' > %t.inf.jsonl
// RUN: echo '{"schema":"s2c2.measured_storage_cost.v1","profile":"rtx4090","workload_class":"storage-aware-pipeline","candidate_signature":"MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PRESERVE|TRANSFER","measured_time_us":2,"repetitions":1,"correctness":1,"source":"device-log","measured":"inferred","note":"inferred is not ranking"}' >> %t.inf.jsonl
// RUN: python3 %S/../../runtime/record_evidence.py --ingest-measured-v1 %t.inf.jsonl --db %t.st.jsonl --measurement-revision=status-inferred
// RUN: python3 %S/../../runtime/record_evidence.py --query-evidence --db %t.st.jsonl --measurement-revision=status-inferred | FileCheck %s --check-prefix=INFERRED
// RUN: echo '{"schema":"s2c2.measured_storage_cost.v1","profile":"rtx4090","workload_class":"storage-aware-pipeline","candidate_signature":"MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PREFETCH|TRANSFER","measured_time_us":1,"repetitions":1,"correctness":1,"source":"synthetic-test","measured":"yes","note":"not device-log"}' > %t.inv.jsonl
// RUN: echo '{"schema":"s2c2.measured_storage_cost.v1","profile":"rtx4090","workload_class":"storage-aware-pipeline","candidate_signature":"MATERIALIZE//MATERIALIZE//MATERIALIZE|TRANSFER//PRESERVE|TRANSFER","measured_time_us":2,"repetitions":1,"correctness":1,"source":"synthetic-test","measured":"yes","note":"not device-log"}' >> %t.inv.jsonl
// RUN: python3 %S/../../runtime/record_evidence.py --ingest-measured-v1 %t.inv.jsonl --db %t.st.jsonl --measurement-revision=status-invalid
// RUN: python3 %S/../../runtime/record_evidence.py --query-evidence --db %t.st.jsonl --measurement-revision=status-invalid | FileCheck %s --check-prefix=INVALID
// RUN: python3 %S/../../runtime/record_evidence.py --ingest-measured-v1 %S/../../docs/design/v3-dataset/hardware-ledger.jsonl --db %t.led.jsonl --measurement-revision=not-ledger | FileCheck %s --check-prefix=LEDGER
// RUN: sed 's/}$/,"extra_key":"no"}/' %S/../../docs/design/v3-dataset/storage-measured-v1.jsonl > %t.extra-v1.jsonl
// RUN: python3 %S/../../runtime/record_evidence.py --ingest-measured-v1 %t.extra-v1.jsonl --db %t.extra.jsonl --measurement-revision=fixture-extra
// RUN: python3 %S/../../runtime/record_evidence.py --check-evidence-db --db %t.extra.jsonl | FileCheck %s --check-prefix=DROPEX
// RUN: not grep extra_key %t.extra.jsonl
// RUN: echo '{"schema":"s2c2.measured_storage_cost.v1","profile":"rtx4090","workload_class":"storage-aware-pipeline","candidate_signature":"NOT_IN_F","measured_time_us":1,"repetitions":1,"correctness":1,"source":"device-log","measured":"yes","note":"must not expand F"}' >> %t.a4090.jsonl
// RUN: s2c2-opt %S/storage-aware-pipeline.mlir --profile=rtx4090 --schedule-policy=measured-storage-v1 --measured-cost-table=%t.a4090.jsonl --check-s2c2-execution 2>&1 | grep -E 's2c2-schedule-policy|hierarchy-global-measured ranked' | FileCheck %s --check-prefix=NOEXPAND
// RUN: python3 %S/../../runtime/record_evidence.py --check-evidence-db --db %S/../../docs/design/v3-dataset/evidence-db.jsonl >/dev/null
// RUN: head -n 1 %S/../../docs/design/v3-dataset/evidence-db.jsonl > %t.dup.jsonl
// RUN: head -n 1 %S/../../docs/design/v3-dataset/evidence-db.jsonl >> %t.dup.jsonl
// RUN: not python3 %S/../../runtime/record_evidence.py --check-evidence-db --db %t.dup.jsonl 2>&1 | FileCheck %s --check-prefix=DUP
// RUN: head -n 1 %S/../../docs/design/v3-dataset/evidence-db.jsonl | sed 's/}$/,"extra_key":"no"}/' > %t.extra-e.jsonl
// RUN: not python3 %S/../../runtime/record_evidence.py --check-evidence-db --db %t.extra-e.jsonl 2>&1 | FileCheck %s --check-prefix=EXTRA
// RUN: s2c2-opt %S/storage-aware-pipeline.mlir --profile=rtx4090 --schedule-policy=measured-storage-v1 --measured-cost-table=%t.a4090.jsonl --s2c2-lower | FileCheck %s --check-prefix=LOWER

// Phase 6B Evidence DB / Contract. Campaign JSONL becomes a
// versioned store with identity E=(profile, workload, candidate,
// measurement_revision). Only measurement_status=measured and
// correctness=1 is ranking evidence. The compiler still consumes
// the v1 projection. 5A-5D stay frozen. 5E is not opened.
// Capacity-aware residency is 6C, not this cut.
// Do not FileCheck microseconds.

// CONTRACT: evidence-db compiler-facing=yes
// CONTRACT: schema s2c2.evidence.v1
// CONTRACT: identity E=(profile,workload,candidate,measurement_revision)
// CONTRACT: status measured|inferred|fixture|pending|invalid
// CONTRACT: note ranking-status-measured-only
// CONTRACT: note compiler-consumes-v1-projection
// CONTRACT: note compiler-ne-campaign-log
// CONTRACT: note extras-cannot-expand-F
// CONTRACT: note measured-ne-rewrite-license
// CONTRACT: note default-3g-frozen
// CONTRACT: note cost-v04-structural-frozen
// CONTRACT: note five-e-not-opened
// CONTRACT: note campaign-5a-5d-frozen
// CONTRACT: note not-capacity-aware
// CONTRACT: note not-hardware-ledger
// CONTRACT: note do-not-filecheck-microseconds
// CONTRACT: cost=unchanged
// CONTRACT-NOT: password
// CONTRACT-NOT: 223.72
// CONTRACT-NOT: 106.75

// POL: note production-path-6a
// POL: note evidence-db-v1
// POL: note not-capacity-aware
// POL: cost=unchanged

// DB: evidence-db check=ok records=38
// DB: evidence-db measured=36 fixture=2 other=0
// DB: evidence-db note identity-E-unique
// DB: evidence-db note ranking-status-measured-only
// DB: evidence-db note not-hardware-ledger
// DB: evidence-db note not-cap-schema-v1
// DB: cost=unchanged
// DB-NOT: password
// DB-NOT: 8495
// DB-NOT: 10303
// DB-NOT: 6791

// INGEST: evidence-db ingest=frozen-campaign records=38
// INGEST: evidence-db note 5a-5d-frozen
// INGEST: evidence-db note five-e-not-opened
// INGEST: cost=unchanged

// FIXING: evidence-db ingest=measured-v1 revision=fixture-v1 rows=2
// FIXING: evidence-db note ranking-status-measured-only

// FIXTURE: evidence-db status=fixture
// FIXTURE: evidence-db ranking-eligible=no
// FIXTURE: evidence-db note measured-ne-rewrite-license
// FIXTURE: evidence-db note five-e-not-opened

// FIXEXP: evidence-db export=measured-v1{{.*}}rows=0
// FIXEXP: evidence-db note ranking-status-measured-only
// FIXEXP: evidence-db note compiler-consumes-v1-projection

// EXP5A: evidence-db export=measured-v1 profile=rtx4090 workload=storage-aware-pipeline revision=5a-pipeline-4090 rows=2
// EXP5A: evidence-db note do-not-filecheck-microseconds
// EXP5A-NOT: 25420
// EXP5A-NOT: 25657

// RANK: hierarchy-global-measured-schedule enumerated=yes truncated=no
// RANK-SAME: ranked-eq-default-3g=yes
// RANK: hierarchy-global-measured-diverge diverge=no
// RANK: s2c2-schedule-policy name=measured-storage-v1{{.*}}applicable=yes{{.*}}rewrite=no
// RANK: s2c2-schedule-policy coincide-default-3g=yes reason=measured-cost-argmin rewrite=no
// RANK-NOT: 25420
// RANK-NOT: 8495
// RANK-NOT: sched.wait

// Q5D: evidence-db query=applicability
// Q5D: evidence-db hits=4 ranking-eligible=4
// Q5D: evidence-db status=measured
// Q5D: evidence-db ranking-eligible=yes revision=5d-loop-4090
// Q5D: evidence-db note measured-ne-rewrite-license
// Q5D-NOT: 8495
// Q5D-NOT: 13713

// ABSENT: evidence-db hits=0 ranking-eligible=0
// ABSENT: evidence-db status=absent
// ABSENT: evidence-db ranking-eligible=no

// PENDING: evidence-db status=pending
// PENDING: evidence-db ranking-eligible=no

// NOEXP: evidence-db export=measured-v1{{.*}}rows=0

// INFERRED: evidence-db status=inferred
// INFERRED: evidence-db ranking-eligible=no

// INVALID: evidence-db status=invalid
// INVALID: evidence-db ranking-eligible=no

// LEDGER: evidence-db ingest=measured-v1 revision=not-ledger rows=0

// DROPEX: evidence-db check=ok records=2
// DROPEX: evidence-db measured=0 fixture=2

// NOEXPAND: hierarchy-global-measured ranked={{.*}}PREFETCH
// NOEXPAND: s2c2-schedule-policy name=measured-storage-v1{{.*}}rewrite=no
// NOEXPAND-NOT: ranked=NOT_IN_F

// DUP: duplicate identity E
// DUP-NOT: check=ok

// EXTRA: extra keys
// EXTRA-NOT: check=ok

// LOWER: memref.copy
// LOWER-NOT: sched.wait
// LOWER-NOT: comm.stream

module {
}
