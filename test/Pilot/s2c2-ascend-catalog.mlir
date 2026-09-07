// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-cap-schema %S/../../docs/design/v3-dataset/ascend910b/capability.jsonl | FileCheck %s
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --query-cap 'C||HtoD' --cap-catalog %S/../../docs/design/v3-dataset/ascend910b/capability.jsonl | FileCheck %s --check-prefix=QH
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --query-cap 'C||C' --cap-catalog %S/../../docs/design/v3-dataset/ascend910b/capability.jsonl | FileCheck %s --check-prefix=QC
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --query-cap 'HtoD||DtoH' --cap-catalog %S/../../docs/design/v3-dataset/ascend910b/capability.jsonl | FileCheck %s --check-prefix=QD
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --check-schema-identity | FileCheck %s --check-prefix=ID

// Measured 910B catalog. Topology only. Do not FileCheck microseconds.
module {
}

// CHECK: v3-cap-schema v1 records=3 hardware=ascend-scope
// CHECK: pair	C||HtoD	underdetermined	none	measured
// CHECK: pair	C||C	underdetermined	none	measured
// CHECK: pair	HtoD||DtoH	mixed	none	measured
// CHECK: no-extra-key acl_davinci
// CHECK: v3=not-claimed
// CHECK: cost=unchanged
// CHECK-NOT: hardware=sm89
// CHECK-NOT: confidence	unknown
// CHECK-NOT: password
// CHECK-NOT: Cost v0.4
// CHECK-NOT: A_us

// QH: "pair":"C||HtoD"
// QH: "pair_relation":"underdetermined"
// QH: "confidence":"measured"
// QH: "hardware_id":"ascend910b:ascend"
// QH-NOT: "hardware_id":"sm89:rtx4090"
// QH-NOT: password

// QC: "pair":"C||C"
// QC: "pair_relation":"underdetermined"
// QC: "confidence":"measured"
// QC: "applicable":false
// QC-NOT: "pair_relation":"parallel"
// QC-NOT: password

// QD: "pair":"HtoD||DtoH"
// QD: "pair_relation":"mixed"
// QD: "confidence":"measured"
// QD-NOT: password

// ID: schema-identity v1 fields=21
// ID: no-extra-key=acl_davinci
// ID: cost=unchanged
