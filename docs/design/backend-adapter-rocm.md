# S²C² ROCm Capability Adapter (Phase 3B / PR-R1)

**Status:** measurement adapter. Not a compiler backend. Not Cost v0.4.
Does **not** change HB, `R`, Search, Transformation, Pilot A/B/C,
`--cuda-val*` timed bodies, Capability Schema keys, or
`--s2c2-capability-schedule`.

```text
Same S²C² IR
+ Same Capability Schema
+ Same Scheduler
+ Different ROCm Capability
→ Different Schedule          # PR-R3, not this increment
```

This increment only builds the **ROCm measurement entry**:

```text
S²C² workload contract  →  HIP realization  →  CapabilityRecord
```

```text
Adapter          ≠  compiler backend
Adapter          ≠  Search / Transform / Cost
Workload_semantic ≠  Kernel_backend
Schema keys      ≠  hip_xxx / amdgpu_xxx
V3               ≠  claimed
```

---

## 1. Why a second vendor, not a CUDA port

Phase 3A proved Capability → Applicability → Schedule on one
NVIDIA GPU. Phase 3B asks whether the **same record type** can
host a second real vendor without new schema keys.

NVIDIA GPU and AMD GPU share a similar shape:

```text
Compute
Device Memory
Host Transfer
Async Stream / Queue
Event
```

Their execution capability is **not** assumed identical. The
adapter measures three pairs. It does not copy 4090 SiLU / tiled
GEMM names, and it does not claim ROCm is faster or slower.

```text
Hardware Agnostic   ≠   Hardware Universal
Capability(4090)    ≠   Capability(AMD)
```

---

## 2. First-cut pairs (only these)

Do not reproduce the 4090 matrix. Measure:

| ID | Pair (schema name) | Arms |
| -- | ------------------ | ---- |
| R1 | `C\|\|HtoD` | elemwise ∥ host_to_device |
| R2 | `C\|\|C` | elemwise ∥ elemwise |
| R3 | `HtoD\|\|DtoH` | host_to_device ∥ device_to_host |

Singles needed to classify a concurrent pair are part of the
harness (`compute`, `htod`, `dtoh`). They are not extra research
cells.

Classifier (same slack as the 4090 recorder; measurement, not a
Cost axiom):

```text
par/sum ≥ 0.90                         →  serial
par/max ≤ 1.15  and  par/sum ≤ 0.75    →  parallel
else                                   →  mixed
```

`observed_constraint` inference after a verdict:

```text
parallel / mixed / underdetermined  →  none
serial + compute-only pair          →  resource_contention
serial + transfer-only pair         →  copy_engine_contention
```

Do not FileCheck microseconds. Do not compare 4090 μs to ROCm μs
in this phase.

---

## 3. Workload contract

A measurement arm is a **semantic contract**, then a vendor
realization:

```text
Compute arm
    semantic = elemwise
    payload  = N f32
    output   = N f32

Transfer arm
    semantic = host_to_device | device_to_host
    bytes    = 4N
    source / dest memory class = pinned_host / device_memory
```

HIP implements `elemwise` as a unary kernel
`y ← 2y+1` repeated `k` times. That is a realization, not a
schema field and not a CUDA SiLU port.

```text
comp.elemwise     ≠  silu
comp.elemwise     ≠  tiled GEMM
comm.stream HtoD  ≠  hipMemcpyAsync          # map, not identity
```

The map is printed by the host protocol. Schema keys stay the
frozen v1 list.

---

## 4. CapabilityRecord

Same type as `docs/design/v3-capability-schema.v1.json`.

Allowed **values** (not keys):

```text
hardware_id       gfxXXXX:amd   (or unfilled on the host)
compute_domain    rocm_cu | none
transfer_domain   copy_engine | none
```

Forbidden:

```text
hip_*
amdgpu_*
any extra JSON key
copying a 4090 record and rewriting hardware_id
```

Host `--emit-record` writes `confidence=unknown` and
`pair_relation=underdetermined`. A later HIP sweep (PR-R2) may
write `confidence=measured`. This increment does **not** invent
AMD pair_relation cells.

Foreign-hardware guard:

```text
hardware_id contains 4090 / sm89  →  reject as an AMD record
```

---

## 5. HIP construct map (HB-preserving)

| S²C² | HIP realization |
| ---- | --------------- |
| `stor.pack` into host | `hipHostMalloc` |
| `comm.stream` host→device | `hipMemcpyAsync` HostToDevice |
| `comm.stream` device→host | `hipMemcpyAsync` DeviceToHost |
| `sched.wait` | `hipEventSynchronize` |
| `comp.elemwise` | unary kernel on a stream |
| Concurrent siblings | two `hipStreamNonBlocking`; no event between them |

```text
HB_source ⊆ HB_impl
```

The adapter may add device synchronization at timing
boundaries. It must not invent a sibling wait.

Named nonblocking streams are the default synchronization
context (`named-nonblocking`), same as the CUDA decision
default. Do not measure the HIP null stream in this increment.

---

## 6. Correctness

Every timed arm, and every concurrent pair, checks the semantic
result after the timed body:

```text
elemwise:   y[i] = iterate_k(x[i])
HtoD:       device dest == host source
DtoH:       host dest   == device source
pair:       both arms
```

The harness prints `correctness=1` or exits non-zero. Host CI
checks the protocol line, not device data.

---

## 7. Out of scope (this PR)

```text
--s2c2-capability-schedule changes
ROCm catalog projection (PR-R2)
cross-vendor same-IR schedule (PR-R3)
Cost v0.4 / Score_3
D2D / P2P / pipeline depth / SiLU||GEMM
NPU / CIM
claiming V3
absolute performance vs 4090
```

---

## 8. Files

| Path | Role |
| ---- | ---- |
| `tools/s2c2-rocm-adapter/` | host `--dry-run` (no HIP, no LLVM) |
| `runtime/rocm/s2c2_rocm_adapter.cpp` | timed HIP harness |
| `runtime/rocm/record_rocm.py` | schema identity + classifier + emit |
| `test/Pilot/s2c2-rocm-adapter-protocol.mlir` | RA1–RA4 |
| `test/Pilot/s2c2-rocm-cap-schema.mlir` | RS1–RS3 |

Machine checks:

```text
s2c2-rocm-adapter --dry-run
s2c2-rocm-adapter --dry-run --cap-schema
s2c2-rocm-adapter --dry-run --classify=10:10:10
runtime/rocm/record_rocm.py --print-cap-schema-v1
runtime/rocm/record_rocm.py --check-schema-identity
```
