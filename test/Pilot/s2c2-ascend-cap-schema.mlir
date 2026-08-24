// RUN: s2c2-ascend-adapter --dry-run --cap-schema 2>&1 | FileCheck %s
// RUN: s2c2-cuda-adapter --dry-run --cap-schema 2>&1 | FileCheck %s --check-prefix=CUDA
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --print-cap-schema-v1 | FileCheck %s --check-prefix=SCHEMA
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --check-schema-identity | FileCheck %s --check-prefix=ID
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --analyze-cap-schema %S/ascend-cap-fixture.jsonl | FileCheck %s --check-prefix=AN
// RUN: not python3 %S/../../runtime/ascend/record_ascend.py --analyze-cap-schema %S/ascend-cap-extra-key.jsonl 2>&1 | FileCheck %s --check-prefix=BAD
// RUN: python3 %S/../../runtime/ascend/record_ascend.py --emit-record 'C||HtoD' | FileCheck %s --check-prefix=EMIT
// RUN: not python3 %S/../../runtime/ascend/record_ascend.py --accept-hardware sm89:rtx4090 | FileCheck %s --check-prefix=FOR

// Schema identity: Ascend adapter fills Capability Schema v1.
// No acl_* keys. No measured 910B pair_relation in this increment.
module {
}

// CHECK: s2c2-ascend-adapter dry-run=1
// CHECK: s2c2-ascend-adapter cap-schema=v1
// CHECK: s2c2-ascend-adapter cap-schema field=compute_domain
// CHECK: s2c2-ascend-adapter cap-schema field=transfer_domain
// CHECK: s2c2-ascend-adapter cap-schema field=direction
// CHECK: s2c2-ascend-adapter cap-schema field=source_memory_class
// CHECK: s2c2-ascend-adapter cap-schema field=destination_memory_class
// CHECK: s2c2-ascend-adapter cap-schema field=pair_relation
// CHECK: s2c2-ascend-adapter cap-schema field=regime
// CHECK: s2c2-ascend-adapter cap-schema field=size_range
// CHECK: s2c2-ascend-adapter cap-schema field=synchronization
// CHECK: s2c2-ascend-adapter cap-schema field=pipeline_depth_evidence
// CHECK: s2c2-ascend-adapter cap-schema field=observed_constraint
// CHECK: s2c2-ascend-adapter cap-schema field=confidence
// CHECK: s2c2-ascend-adapter cap-schema hardware=unfilled
// CHECK: s2c2-ascend-adapter cap-schema no-extra-key=acl_davinci
// CHECK: s2c2-ascend-adapter cap-schema depth-star=not-a-law
// CHECK: s2c2-ascend-adapter cap-schema cost=unchanged
// CHECK: s2c2-ascend-adapter cap-schema semantics=unchanged
// CHECK-NOT: field=acl_
// CHECK-NOT: field=davinci_
// CHECK-NOT: field=cube_
// CHECK-NOT: password

// CUDA: s2c2-cuda-adapter cap-schema=v1
// CUDA: s2c2-cuda-adapter cap-schema field=compute_domain
// CUDA: s2c2-cuda-adapter cap-schema field=observed_constraint
// CUDA: s2c2-cuda-adapter cap-schema cost=unchanged
// CUDA-NOT: field=acl_

// SCHEMA: cap-schema v1
// SCHEMA: field compute_domain
// SCHEMA: source_memory_class
// SCHEMA: observed_constraint
// SCHEMA: pair_relation parallel serial mixed underdetermined
// SCHEMA: hardware unfilled
// SCHEMA: no-extra-key acl_davinci
// SCHEMA: semantics unchanged
// SCHEMA: v3=not-claimed
// SCHEMA: cost=unchanged

// ID: schema-identity v1 fields=21 additionalProperties=false
// ID: no-extra-key=acl_davinci
// ID: vendor=ascend-or-cuda
// ID: v3=not-claimed
// ID: cost=unchanged

// AN: v3-cap-schema v1 records=3 hardware=ascend-scope
// AN: pair	C||HtoD	underdetermined
// AN: pair	C||C	underdetermined
// AN: pair	HtoD||DtoH	underdetermined
// AN: no-extra-key acl_davinci
// AN: semantics unchanged
// AN: v3=not-claimed
// AN-NOT: pair_relation	serial
// AN-NOT: confidence	measured
// AN-NOT: Cost v0.4

// BAD: record_ascend: invalid cap-schema
// BAD: extra acl_stream

// EMIT: "compute_domain":"ascend_ai_core"
// EMIT: "pair_relation":"underdetermined"
// EMIT: "confidence":"unknown"
// EMIT: record_ascend emit-record pair=C||HtoD confidence=unknown
// EMIT-NOT: acl_
// EMIT-NOT: "confidence":"measured"

// FOR: record_ascend foreign-hardware=rejected id=sm89:rtx4090
// FOR: record_ascend note capability-4090-ne-capability-910b
