// RUN: s2c2-cuda-adapter --dry-run --cap-schema 2>&1 | FileCheck %s
// RUN: s2c2-cuda-adapter --dry-run 2>&1 | FileCheck %s --check-prefix=ABC
// RUN: s2c2-cuda-adapter --dry-run --cap 2>&1 | FileCheck %s --check-prefix=CAP
// RUN: python3 %S/../../runtime/cuda/record_v3.py --print-cap-schema-v1 | FileCheck %s --check-prefix=SCHEMA
// RUN: python3 %S/../../runtime/cuda/record_v3.py --analyze-cap-schema %S/cap-schema-fixture.jsonl | FileCheck %s --check-prefix=AN
// RUN: python3 %S/../../runtime/cuda/record_v3.py --analyze-cap-schema %S/../../docs/design/v3-dataset/v3-cap-schema-4090.jsonl | FileCheck %s --check-prefix=HW
// RUN: python3 %S/../../runtime/cuda/record_v3.py --query-cap C||HtoD --cap-catalog %S/../../docs/design/v3-dataset/v3-cap-schema-4090.jsonl | FileCheck %s --check-prefix=Q1
// RUN: python3 %S/../../runtime/cuda/record_v3.py --query-cap C_silu||C_gemm --cap-catalog %S/../../docs/design/v3-dataset/v3-cap-schema-4090.jsonl | FileCheck %s --check-prefix=Q2
// RUN: python3 %S/../../runtime/cuda/record_v3.py --print-cap-schema | FileCheck %s --check-prefix=OLD

// Host + recorder protocol for Capability Schema v1.
// Hardware-neutral record type. No device, no microseconds FileCheck, no Cost.
module {
}

// CHECK: s2c2-cuda-adapter dry-run=1
// CHECK: s2c2-cuda-adapter cap-schema=v1
// CHECK: s2c2-cuda-adapter cap-schema field=compute_domain
// CHECK: s2c2-cuda-adapter cap-schema field=transfer_domain
// CHECK: s2c2-cuda-adapter cap-schema field=direction
// CHECK: s2c2-cuda-adapter cap-schema field=source_memory_class
// CHECK: s2c2-cuda-adapter cap-schema field=destination_memory_class
// CHECK: s2c2-cuda-adapter cap-schema field=pair_relation
// CHECK: s2c2-cuda-adapter cap-schema field=size_range
// CHECK: s2c2-cuda-adapter cap-schema field=regime
// CHECK: s2c2-cuda-adapter cap-schema field=synchronization
// CHECK: s2c2-cuda-adapter cap-schema field=pipeline_depth_evidence
// CHECK: s2c2-cuda-adapter cap-schema field=observed_constraint
// CHECK: s2c2-cuda-adapter cap-schema field=confidence
// CHECK: s2c2-cuda-adapter cap-schema hardware=unfilled
// CHECK: s2c2-cuda-adapter cap-schema depth-star=not-a-law
// CHECK: s2c2-cuda-adapter cap-schema cost=unchanged
// CHECK: s2c2-cuda-adapter cap-schema semantics=unchanged
// CHECK: s2c2-cuda-adapter v3=not-claimed
// CHECK-NOT: func=pilot_a
// CHECK-NOT: cap=htod
// CHECK-NOT: password

// ABC: s2c2-cuda-adapter func=pilot_a_ssd_hbm_compute
// ABC: s2c2-cuda-adapter func=pilot_b_compute_par_comm
// ABC: s2c2-cuda-adapter func=pilot_c_pipeline_three_stage
// ABC-NOT: cap-schema=v1
// ABC-NOT: pipe=d1

// CAP: s2c2-cuda-adapter cap=htod remaining=1xHtoD
// CAP: s2c2-cuda-adapter cap cost=unchanged
// CAP-NOT: cap-schema=v1

// SCHEMA: cap-schema v1
// SCHEMA: field compute_domain
// SCHEMA: source_memory_class
// SCHEMA: observed_constraint
// SCHEMA: transfer_domain copy_engine
// SCHEMA: pair_relation parallel serial mixed underdetermined
// SCHEMA-NOT: pinned_htod
// SCHEMA-NOT: same_HtoD
// SCHEMA: hardware unfilled
// SCHEMA: depth-star not-a-law
// SCHEMA: semantics unchanged
// SCHEMA: v3=not-claimed
// SCHEMA: cost=unchanged

// AN: v3-cap-schema v1 records=2 hardware=unfilled,fixture-b
// AN: pair
// AN: C||HtoD
// AN: underdetermined
// AN: serial
// AN: depth-star not-a-law
// AN: semantics unchanged
// AN: v3=not-claimed
// AN-NOT: Cost v0.4
// AN-NOT: password

// Qualitative 4090 projection only. Do not FileCheck microseconds.
// HW: v3-cap-schema v1 records=12 hardware=rtx4090
// HW: pair	C||HtoD	parallel
// HW: pair	HtoD||DtoH	mixed
// HW: pair	C||C	serial
// HW: pair	C_silu||C_gemm	serial	resource_contention
// HW: pipeline	C||HtoD	saturates:2
// HW: depth-star not-a-law
// HW: semantics unchanged
// HW: v3=not-claimed
// HW-NOT: Cost v0.4
// HW-NOT: password

// Q1: "pair": "C||HtoD"
// Q1: "pair_relation": "parallel"
// Q1: "observed_constraint": "none"
// Q1: "confidence": "measured"
// Q1: "applicable": "unknown"

// Q2: "pair": "C_silu||C_gemm"
// Q2: "pair_relation": "serial"
// Q2: "observed_constraint": "resource_contention"
// Q2: "confidence": "arm_specific"
// Q2: "applicable": false

// OLD: cap-arm pairs sync size intensity
// OLD: v3=not-claimed
// OLD-NOT: cap-schema v1
