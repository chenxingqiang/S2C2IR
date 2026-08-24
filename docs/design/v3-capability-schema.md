# V3 Capability Schema v1

Status: **schema + 4090 projection**. Not Cost v0.4. Does
**not** change Cost, HB, `R`, Search, Transformation, Pilot
IR, A/B/C bodies, `--matched` / `--phase` / `--cap` /
`--pipe` timed bodies, or the frozen `#55`–`#58` tables.
Baseline: `751dd11` (`#58`). Semantics stay
[`execution-semantics.md`](execution-semantics.md) /
[`pipeline-semantics.md`](pipeline-semantics.md).

```text
Capability Schema v1   ≠  a Cost axiom
--cap-schema           ≠  a new Pilot func
4090 projection        ≠  a new measurement
depth* = N_resource    ≠  a law
S²C² Semantics         =  unchanged
V3                     ≠  claimed
```

---

## 1. Why this layer

`#55`–`#58` froze one machine:

```text
Capability_4090
    →  Phase(C ∥ HtoD)
    →  Pipeline depth
    →  Tile-count robustness
```

That chain is **evidence**, not a portable type. The next
hardware (AMD GPU / 国产 GPU / NPU / CIM / FPGA) must not
reinvent the experiment book. It must fill the **same
record** so a later comparison is:

```text
Capability(hardware_1)  ≠  Capability(hardware_2)
```

and **not**:

```text
new_framework(hardware_2)
```

This increment defines that record. It does **not** open
Cost v0.4, and it does not claim the 4090 cells are
universal.

---

## 2. Record

One JSON object. Closed vocabularies. Extra keys (`pair`,
`note`, `evidence_refs`) are allowed; the twelve fields
below are required.

| Field | Closed vocabulary / form |
| ----- | ------------------------ |
| `schema_version` | `v1` |
| `record_kind` | `pair` / `transfer` / `sync` / `phase` / `pipeline` |
| `hardware_id` | `unfilled` or a device tag (`rtx4090`, …) |
| `compute_domain` | `elementwise_silu` / `reduction` / `matmul` / `none` |
| `transfer_domain` | `pinned_htod` / `pinned_dtoh` / `pinned_both` / `none` |
| `direction` | `HtoD` / `DtoH` / `bidirectional` / `same_HtoD` / `same_DtoH` / `none` |
| `pair_relation` | `parallel` / `serial` / `mixed` / `underdetermined` / `unmeasured` |
| `size_range` | `unmeasured` or a payload band |
| `regime` | `pair_matrix` / `size_curve` / `idle_sync` / `phase_r_N` / `pipe_depth_tiles` / `unmeasured` |
| `synchronization` | `unmeasured` or a sync-slot note |
| `pipeline_depth_evidence` | `unmeasured` or a depth/tiles note |
| `confidence` | `measured` / `arm_specific` / `projected` / `unmeasured` |

Every record also carries:

```text
v3         = not-claimed
cost       = unchanged
semantics  = unchanged
```

What the fields are **for** (hardware-agnostic):

```text
pair capability              pair_relation
directionality               direction
size dependence              size_range + regime=size_curve
r dependence                 regime=phase_r_N
fixed latency                transfer note (T_fixed + bytes/BW)
synchronization cost         synchronization
pipeline depth saturation    pipeline_depth_evidence
```

`pair_relation` uses the **measurement policy** already
frozen on `#55`/`#56` (`hid_short=1.15`, `near_sum=0.90`).
That policy is not a physical constant and is not a Cost
axiom. Future devices may keep the same policy or bind
thresholds to their own variance; they still use this
schema.

```text
canOverlap=true     ≠  a device-wide boolean
C∥C = serial        ≠  ∀ compute   (arm_specific)
saturated@2         ≠  ∀ pipeline  (this regime only)
depth* = N_resource ≠  claimed
```

A blank (`hardware_id=unfilled`) record is how a second
machine starts. Filling it is a later increment.

---

## 3. 4090 projection (not a new sweep)

`--project-cap-schema-v1` reads the frozen derived tables
and writes one catalog. No CUDA, no new microseconds.

| kind | cells | source |
| ---- | ----- | ------ |
| pair | 6 | `v3-cap-pairs.csv` (`#55`) |
| transfer | 2 | `#55` size-curve shape |
| sync | 1 | `#55` idle-sync slot |
| phase | 1 | `v3-phase-slices.csv` (`#56`) |
| pipeline | 1 | `v3-pipe-tiles-slices.csv` (`#57`+`#58`) |

11 records. `C∥C` is `confidence=arm_specific`. Pipeline
cell says `saturated_at=2` **under this tested regime**
(`depths=1..4`, `tiles=4..32`, C∥HtoD, this SiLU arm).
It does **not** say `depth*=N_resource`.

JSON Schema: [`v3-capability-schema.v1.json`](v3-capability-schema.v1.json).
4090 catalog:
[`v3-dataset/v3-cap-schema-4090.jsonl`](v3-dataset/v3-cap-schema-4090.jsonl).

Do not FileCheck microseconds.

---

## 4. Out of this increment

```text
Cost v0.4 / C_overlap / Score_3
new 4090 measurement
AMD / NPU / CIM / FPGA fill-in
rewriting Capability_4090 tables
changing S²C² Semantics
claiming V3
```

---

## 5. Files

| Path | Role |
| ---- | ---- |
| `tools/s2c2-cuda-adapter/` | host `--dry-run --cap-schema` |
| `runtime/cuda/record_v3.py` | `--print-cap-schema-v1` / `--project-cap-schema-v1` / `--analyze-cap-schema` |
| `docs/design/v3-capability-schema.v1.json` | JSON Schema |
| `docs/design/v3-dataset/v3-cap-schema-4090.jsonl` | 4090 projection |

`--cap` / `--phase` / `--pipe` / `--pipe-tiles` dry-run
banners stay unchanged.

```text
Capability Schema v1  ≠  Cost v0.4
4090 instance         ≠  ∀ hardware
Semantics             =  unchanged
V3                    ≠  claimed
```
