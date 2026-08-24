// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-cap-schema %S/../../docs/design/v3-dataset/ascend910b/cc-size-applicability.jsonl | FileCheck %s --check-prefix=AN
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --query-cap 'C||C' --cap-catalog %S/../../docs/design/v3-dataset/ascend910b/cc-size-applicability.jsonl | FileCheck %s --check-prefix=Q0
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --query-cap 'C||C' --cap-catalog %S/../../docs/design/v3-dataset/ascend910b/cc-size-applicability.jsonl --n 4194304 | FileCheck %s --check-prefix=QM
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --query-cap 'C||C' --cap-catalog %S/../../docs/design/v3-dataset/ascend910b/cc-size-applicability.jsonl --n 16777216 | FileCheck %s --check-prefix=QT
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --query-cap 'C||C' --cap-catalog %S/../../docs/design/v3-dataset/ascend910b/cc-size-applicability.jsonl --n 33554432 | FileCheck %s --check-prefix=QS
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --query-cap 'C||C' --cap-catalog %S/../../docs/design/v3-dataset/ascend910b/capability.jsonl | FileCheck %s --check-prefix=QC
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --check-schema-identity | FileCheck %s --check-prefix=ID

// Size-banded 910B C||C applicability overlay. Schema v1 only.
// #69 catalog stays underdetermined. rewrite_license=no. Not Cost. Not PR-R3.
module {
}

// AN: v3-cap-schema v1 records=3 hardware=ascend-scope
// AN: pair	C||C	mixed	none	measured
// AN: pair	C||C	underdetermined	none	measured
// AN: pair	C||C	serial	resource_contention	measured
// AN: no-extra-key acl_davinci
// AN: v3=not-claimed
// AN: cost=unchanged
// AN-NOT: password
// AN-NOT: Cost v0.4

// Catalog query with no --n does not pick mixed or serial.
// Q0: "pair":"C||C"
// Q0: "pair_relation":"underdetermined"
// Q0: "size_range":"multiple"
// Q0: "applicable":false
// Q0: "rewrite_license":false
// Q0-NOT: password

// N=4M floats = 16MiB payload → mixed band.
// QM: "pair":"C||C"
// QM: "pair_relation":"mixed"
// QM: "phase_band":"mixed"
// QM: "size_range":"16MiB..48MiB"
// QM: "applicable":true
// QM: "rewrite_license":false
// QM-NOT: password

// N=16M floats = 64MiB payload → transition / unknown.
// QT: "pair":"C||C"
// QT: "pair_relation":"underdetermined"
// QT: "phase_band":"transition"
// QT: "size_range":"64MiB..127MiB"
// QT: "applicable":false
// QT: "rewrite_license":false
// QT-NOT: "pair_relation":"serial"
// QT-NOT: password

// N=32M floats = 128MiB payload → serial evidence, not a rewrite license.
// QS: "pair":"C||C"
// QS: "pair_relation":"serial"
// QS: "observed_constraint":"resource_contention"
// QS: "phase_band":"serial"
// QS: "size_range":"128MiB..512MiB"
// QS: "applicable":true
// QS: "rewrite_license":false
// QS-NOT: password

// #69 C||C stays underdetermined.
// QC: "pair":"C||C"
// QC: "pair_relation":"underdetermined"
// QC: "applicable":false
// QC-NOT: "pair_relation":"serial"
// QC-NOT: password

// ID: schema-identity v1 fields=21
// ID: no-extra-key=acl_davinci
// ID: cost=unchanged
