# Capability Schema v1 (hardware-neutral)

**Status:** Frozen for Phase 3A.  
**Not:** Cost v0.4, V3 claim, CUDA Validation V1.

This document freezes one record type. CUDA 4090, a future NPU, and a CIM
fill the **same fields**. Hardware names stay in `hardware_id` and in
`compute_domain` / `transfer_domain` / memory-class **values**, not in
the schema keys.

## CapabilityRecord

```text
CapabilityRecord
├── schema_version              "1"
├── record_kind                 pair | depth | memory | sync
├── hardware_id                 opaque string (e.g. sm89:rtx4090)
├── compute_domain              cuda_sm | npu_core | cim_array | none | …
├── transfer_domain             copy_engine | dma | on_chip_bus | none | …
├── direction                   host_to_device | device_to_host |
│                               device_to_device | device_to_local |
│                               device_to_array | none | …
├── source_memory_class         pinned_host | pageable_host | device_memory |
│                               global_memory | local_buffer | dram |
│                               cim_array | none | …
├── destination_memory_class    (same vocabulary)
├── pair                        C||HtoD | C||DtoH | HtoD||DtoH | C||C | …
├── pair_relation               serial | parallel | mixed | underdetermined
├── regime                      bandwidth | latency | occupancy | underdetermined
├── size_range                  bytes as string, or n/a
├── synchronization             named-nonblocking | legacy-default | n/a
├── pipeline_depth_evidence     saturates:N | n/a
├── observed_constraint         none | legacy_default | resource_contention |
│                               allocator_sync | copy_engine_contention
├── confidence                  measured | inferred | arm_specific | unknown
├── note
├── evidence_refs               comma-separated design docs
├── v3                          not-claimed
├── cost                        unchanged
└── semantics                   unchanged
```

JSON Schema: `docs/design/v3-capability-schema.v1.json`.

CUDA 4090 catalog: `docs/design/v3-dataset/v3-cap-schema-4090.jsonl`.  
Synthetic NPU demo catalog (not measured):
`docs/design/v3-dataset/v3-cap-schema-npu-demo.jsonl`.

## Examples

4090 HtoD:

```text
host_to_device
pinned_host → device_memory
pair_relation = parallel
observed_constraint = none
```

Future NPU:

```text
device_to_local
global_memory → local_buffer
pair_relation = parallel
```

CIM:

```text
device_to_array
dram → cim_array
observed_constraint = resource_contention
```

## Compiler use

The catalog is a **decision input**, not an archive. See
`docs/design/capability-aware-decision.md` and the
`--s2c2-capability-schedule` pass.

Phase 3A does **not** pick the fastest schedule. It filters candidates
that Capability says are not worthwhile to overlap (`serial` /
`resource_contention`).

## Machine checks

```text
s2c2-cuda-adapter --dry-run --cap-schema
runtime/cuda/record_v3.py --print-cap-schema-v1
runtime/cuda/record_v3.py --analyze-cap-schema
```
