# S²C² Ascend 910B Capability Adapter (Phase 3B / PR-R1-Ascend)

**Status:** measurement adapter. Not a compiler backend. Not Cost v0.4.
Does **not** change HB, `R`, Search, Transformation, Pilot A/B/C,
`--cuda-val*` timed bodies, Capability Schema keys, or
`--s2c2-capability-schedule`.

ROCm draft `#67` stays as a later third-vendor adapter. It is **not**
the Phase 3B second hardware. This increment is 4090 → 910B.

```text
Same S²C² IR
+ Same Capability Schema
+ Same Scheduler
+ Different Ascend 910B Capability
→ Different Schedule          # PR-R3, not this increment
```

This increment only builds the **AscendCL measurement entry**:

```text
S²C² workload contract  →  AscendCL realization  →  CapabilityRecord
```

```text
Adapter           ≠  compiler backend
Adapter           ≠  Search / Transform / Cost
Workload_semantic ≠  Kernel_backend
Schema keys       ≠  acl_* / davinci_* / cube_* / vectorcore_*
V3                ≠  claimed
aclgraph / GE     ≠  this increment
```

---

## 1. Why 910B, not ROCm, as the second vendor

4090 and an AMD GPU still share GPU / HBM / Stream / Event shape.
910B is a different heterogeneous execution system. AscendCL still
provides Stream / Event / async memcpy, so S²C² execution semantics
can map, but Capability is expected to differ.

```text
Capability(4090)  ≠  Capability(910B)
Hardware Agnostic ≠  Hardware Universal
```

---

## 2. First-cut pairs (only these)

| ID | Pair (schema name) | Arms |
| -- | ------------------ | ---- |
| R1 | `C\|\|HtoD` | elemwise ∥ host_to_device |
| R2 | `C\|\|C` | elemwise ∥ elemwise |
| R3 | `HtoD\|\|DtoH` | host_to_device ∥ device_to_host |

Pinned vs pageable (R4) is a later PR. Do not copy 4090 SiLU / GEMM.

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

Do not FileCheck microseconds. Do not compare 4090 μs to 910B μs.

---

## 3. Workload contract

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

910B implements `elemwise` as `y ← 2y+1` repeated `k` times on a
stream (unary device op). That is a realization, not a schema field
and not a CUDA SiLU port.

```text
comp.elemwise     ≠  silu
comp.elemwise     ≠  tiled GEMM
comm.stream HtoD  ≠  aclrtMemcpyAsync     # map, not identity
```

---

## 4. CapabilityRecord

Same type as `docs/design/v3-capability-schema.v1.json`.

Allowed **values** (not keys):

```text
hardware_id       ascend910b:ascend   (or unfilled on the host)
compute_domain    ascend_ai_core | none
transfer_domain   copy_engine | none
```

Forbidden:

```text
acl_*
davinci_*
cube_*
vectorcore_*
any extra JSON key
copying a 4090 or ROCm record and rewriting hardware_id
```

Host `--emit-record` writes `confidence=unknown` and
`pair_relation=underdetermined`. A later 910B sweep (PR-R2) may
write `confidence=measured`. This increment does **not** invent
910B pair_relation cells.

Foreign-hardware guard:

```text
hardware_id contains 4090 / sm89 / cuda / gfx / amd / hip  →  reject
```

---

## 5. AscendCL construct map (HB-preserving)

| S²C² | AscendCL realization |
| ---- | -------------------- |
| `stor.pack` into host | `aclrtMallocHost` |
| `comm.stream` host→device | `aclrtMemcpyAsync` HostToDevice |
| `comm.stream` device→host | `aclrtMemcpyAsync` DeviceToHost |
| `sched.wait` | `aclrtRecordEvent` + `aclrtStreamWaitEvent` |
| `comp.elemwise` | unary device op on a stream |
| Concurrent siblings | two `aclrtCreateStream`; no wait between them |

```text
HB_source ⊆ HB_impl
```

Named streams are the default synchronization context
(`named-nonblocking`). Do not measure the default stream in this
increment. Do not use Graph Engine / MindSpore / torch_npu /
`aclgraph`. Concurrent compute arms use **separate** device
buffers and **per-stream** aclnn workspace; a shared workspace
would be a false `C||C` serializer.

### Timing contract

`T_pair` is **host wall-clock** over both work streams (same P0
as the ROCm review: an event recorded on the wrong stream is not
a completion witness):

```text
aclrtSynchronizeStream / device clean boundary
start = steady_clock
launch on s0 / s1
aclrtSynchronizeStream(s0)
aclrtSynchronizeStream(s1)
stop  = steady_clock
T_pair = completion(s0, s1)
```

---

## 6. Correctness

```text
elemwise:   y[i] = iterate_k(x[i])
HtoD:       device dest == host source
DtoH:       host dest   == device source
pair:       both arms
```

The harness prints `correctness=1` or exits non-zero.

---

## 7. Out of scope (this PR)

```text
--s2c2-capability-schedule changes
910B catalog projection (PR-R2)
cross-vendor same-IR schedule (PR-R3)
pinned vs pageable (R4)
Cost v0.4 / Score_3
aclgraph / GE / MindSpore / torch_npu
D2D / pipeline depth / SiLU||GEMM
claiming V3
absolute performance vs 4090
```

A compile smoke on a 910B (`correctness=1`) is **not** a
catalog. Tiny-N `pair_relation` is not committed and is not
FileChecked. Measured cells belong in PR-R2.

---

## 8. Files

| Path | Role |
| ---- | ---- |
| `tools/s2c2-ascend-adapter/` | host `--dry-run` (no CANN, no LLVM) |
| `runtime/ascend/s2c2_ascend_adapter.cpp` | timed AscendCL harness |
| `runtime/ascend/record_ascend.py` | schema identity + classifier + emit |
| `test/Pilot/s2c2-ascend-adapter-protocol.mlir` | AA1–AA4 |
| `test/Pilot/s2c2-ascend-cap-schema.mlir` | AS1–AS3 |

Machine checks:

```text
s2c2-ascend-adapter --dry-run
s2c2-ascend-adapter --dry-run --cap-schema
s2c2-ascend-adapter --dry-run --classify=10:10:10
runtime/ascend/record_ascend.py --print-cap-schema-v1
runtime/ascend/record_ascend.py --check-schema-identity
```
