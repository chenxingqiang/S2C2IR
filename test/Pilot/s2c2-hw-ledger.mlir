// RUN: python3 %S/../../runtime/record_hw_ledger.py --print-hw-ledger-contract | FileCheck %s --check-prefix=CONTRACT
// RUN: python3 %S/../../runtime/record_hw_ledger.py --check-hw-ledger | FileCheck %s --check-prefix=LEDGER
// RUN: not python3 %S/../../runtime/record_hw_ledger.py --check-hw-ledger %S/hw-ledger-missing-fixture.jsonl 2>&1 | FileCheck %s --check-prefix=MISS
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --query-cap 'C||C' --cap-catalog %S/../../docs/design/v3-dataset/ascend910b/capability.jsonl | FileCheck %s --check-prefix=QC

// Hardware measurement ledger: keep original paths, check them together.
// Do not FileCheck microseconds. Do not overwrite #69. Not Cost.

module {
}

// CONTRACT: hw-ledger batch-check=yes
// CONTRACT: hw-ledger note keep-original-path
// CONTRACT: hw-ledger note not-cap-schema-v1
// CONTRACT: hw-ledger note catalog-untouched
// CONTRACT: hw-ledger note npu-demo=not-ledger
// CONTRACT: hw-ledger note pending=device-absent
// CONTRACT: cost=unchanged
// CONTRACT-NOT: Cost v0.4
// CONTRACT-NOT: password

// LEDGER: hw-ledger id=rtx4090-cap-schema status=measured files=ok
// LEDGER: hw-ledger id=ascend910b-catalog-69 status=measured files=ok
// LEDGER: hw-ledger id=ascend910b-overlay status=measured files=ok
// LEDGER: hw-ledger id=ascend910b-cc-rewrite status=measured files=ok
// LEDGER: hw-ledger id=ssd-mlp-wallclock status=measured files=ok
// LEDGER: hw-ledger id=ssd-mlp-wallclock-4090 status=measured files=ok
// LEDGER: hw-ledger id=storage-pipeline-4090 status=measured files=ok
// LEDGER: hw-ledger id=storage-loop-wallclock-4090 status=device-absent files=ok
// LEDGER: hw-ledger id=storage-loop-wallclock status=device-absent files=ok
// LEDGER: hw-ledger records=23
// LEDGER: hw-ledger measured=21
// LEDGER: hw-ledger device-absent=2
// LEDGER: hw-ledger catalog-69=underdetermined
// LEDGER: hw-ledger catalog-untouched=yes
// LEDGER: hw-ledger secrets=0
// LEDGER: hw-ledger analyzers=ok
// LEDGER: hw-ledger npu-demo=not-ledger
// LEDGER-NOT: hw-ledger ssd-mlp-wallclock=device-absent
// LEDGER-NOT: hw-ledger ssd-mlp-wallclock-4090=device-absent
// LEDGER-NOT: hw-ledger storage-pipeline-4090=device-absent
// LEDGER-NOT: hw-ledger storage-loop-wallclock-4090=measured
// LEDGER-NOT: hw-ledger storage-loop-wallclock=measured
// LEDGER: cost=unchanged
// LEDGER-NOT: Cost v0.4
// LEDGER-NOT: password
// LEDGER-NOT: A_us

// MISS: missing path
// MISS-NOT: Cost v0.4

// QC: "pair":"C||C"
// QC: "pair_relation":"underdetermined"
// QC-NOT: "pair_relation":"parallel"
// QC-NOT: password
