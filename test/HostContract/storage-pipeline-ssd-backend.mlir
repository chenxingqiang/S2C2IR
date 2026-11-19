// --ssd-dir is a file backend. The analyzer reports the backend the
// log names. A file-backed log is not logical-ssd-ne-disk. A log that
// names both is refused. Do not FileCheck microseconds. Not a ledger row.
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-pipeline %S/storage-pipeline-file-backend.log | FileCheck %s --check-prefix=FILE --implicit-check-not=logical-ssd-ne-disk --implicit-check-not=/fixture --implicit-check-not=not-rtx4090-contract --implicit-check-not=seq= --implicit-check-not=evi= --implicit-check-not=par=
// RUN: not python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-pipeline %S/storage-pipeline-backend-both.log
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-pipeline %S/storage-pipeline-backend-missing.log | FileCheck %s --check-prefix=MISS --implicit-check-not=logical-ssd-ne-disk --implicit-check-not=file-odirect
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-pipeline %S/../../docs/design/v3-dataset/storage-pipeline-4090.log | FileCheck %s --check-prefix=PAGE --implicit-check-not=file-odirect

module {
}

// FILE: storage-pipeline program-measurement=yes
// FILE: storage-pipeline measured=yes
// FILE: storage-pipeline t-opt-over-base-defined=yes
// FILE: storage-pipeline ssd-backend=file-odirect
// FILE: storage-pipeline note ssd-mount-has-nvme=no
// FILE: note not-new-capability-grid
// FILE: note not-cost-v04
// FILE: cost=unchanged
// FILE-NOT: logical-ssd-ne-disk
// FILE-NOT: Cost v0.4

// MISS: storage-pipeline note ssd-backend-unspecified
// MISS: cost=unchanged
// MISS-NOT: logical-ssd-ne-disk
// MISS-NOT: file-odirect

// PAGE: note logical-ssd-ne-disk
// PAGE: cost=unchanged
// PAGE-NOT: file-odirect
