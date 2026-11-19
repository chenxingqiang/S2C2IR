// RTX 5090 storage-pipeline observation. Not the 4090 contract.
// The analyzer reports facts already in the log. It does not
// add a ledger row, a Capability cell, or a Cost value.
// Do not FileCheck microseconds.
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-pipeline %S/../../docs/design/v3-dataset/storage-pipeline-5090.log | FileCheck %s --check-prefix=OBS --implicit-check-not=names-disk-path --implicit-check-not=file-odirect --implicit-check-not=seq= --implicit-check-not=evi= --implicit-check-not=par= --implicit-check-not="cost=changed"
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-storage-pipeline %S/../../docs/design/v3-dataset/storage-pipeline-4090.log | FileCheck %s --check-prefix=C4090 --implicit-check-not=not-rtx4090-contract --implicit-check-not=rtx5090 --implicit-check-not=host-wall-clock-ne-hb --implicit-check-not=names-no-disk-path --implicit-check-not=file-odirect

module {
}

// OBS: storage-pipeline program-measurement=yes
// OBS: storage-pipeline measured=yes
// OBS: storage-pipeline t-opt-over-base-defined=yes
// OBS: note logical-ssd-ne-disk
// OBS: note not-new-capability-grid
// OBS: note not-cost-v04
// OBS: storage-pipeline note not-rtx4090-contract
// OBS: storage-pipeline note does-not-replace-4090
// OBS: storage-pipeline note host-wall-clock-ne-hb
// OBS: storage-pipeline hardware_id=rtx5090:cuda
// OBS: storage-pipeline correctness=yes
// OBS: storage-pipeline note names-no-disk-path
// OBS: cost=unchanged
// OBS-NOT: Cost v0.4
// OBS-NOT: password

// C4090: storage-pipeline measured=yes
// C4090: note logical-ssd-ne-disk
// C4090: cost=unchanged
// C4090-NOT: not-rtx4090-contract
// C4090-NOT: rtx5090
