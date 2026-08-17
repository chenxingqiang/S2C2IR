# Phase 1.5 Design: Semantic Normalization

Status: **implementation baseline** (evolves Phase 1 without a rewrite).

Phase 1 proved S²C² can exist as an out-of-tree MLIR dialect family. Phase 1.5
locks down four semantic contracts that later `linalg` / `async` / StableHLO
work must not fight:

1. Logical object vs residency
2. Generic completion events
3. N-way concurrency
4. Target memory-space mapping

Non-goals: StableHLO frontend, IREE, MPI, full codegen.

## 1. Storage identity

Types do **not** carry instance identity. Two values with the same
`!stor.buffer<tensor<...>, hbm>` type may be different objects, different
replicas, or the same replica.

```text
LogicalObject  (!stor.object<tensor<...>>)     SSA identity
      │
      ├── residency  (!stor.buffer<tensor<...>, ssd>)
      └── residency  (!stor.buffer<tensor<...>, hbm>)
```

```mlir
%w = stor.object : !stor.object<tensor<4096x11008xf16>>
%w_ssd = stor.materialize %w
  : !stor.object<tensor<4096x11008xf16>> -> !stor.buffer<tensor<4096x11008xf16>, ssd>
%w_hbm = stor.materialize %w
  : !stor.object<tensor<4096x11008xf16>> -> !stor.buffer<tensor<4096x11008xf16>, hbm>
```

`%w` is the logical datum. `%w_ssd` / `%w_hbm` are residencies (replicas /
handles) of **that** object.

| Op | Meaning |
| -- | ------- |
| `stor.object` | Create a logical identity (no allocation) |
| `stor.materialize` | Allocate a residency of an object in the result space |
| `stor.transfer` | Allocate a new residency and copy payload from an existing one (same object) |
| `stor.alloc` | Anonymous residency (no object). Legacy / local scratch |
| `stor.dealloc` | Free a residency, not the logical object |
| `stor.pack` / `stor.unpack` | Tensor ↔ residency edge |

### Alias / copy contract

Walk `getLogicalObject(buffer)`:

- `materialize %obj` → `%obj`
- `transfer %src` → `getLogicalObject(%src)`
- `alloc` / unknown → empty (anonymous)

`comm.copy` / `comm.stream`:

- Payload types must match
- If **both** sides have a logical object, they must be the **same SSA value**
- Mixing object-backed and anonymous buffers is rejected
- Two anonymous `alloc` buffers remain legal (Phase 1 scratch)

Interpretation:

| Construct | Identity | Allocation |
| --------- | -------- | ---------- |
| Two `materialize`s of `%w` | Same object, two replicas | Independent |
| `comm.copy` / `comm.stream` | Syncs payload between replicas of the same object | Does **not** create a new object; not an alias of the same allocation |
| `stor.transfer` | New replica of the source object | New allocation + copy |
| Two `stor.alloc`s | Distinct anonymous identities | Independent |

Same-space replicas are allowed (`comm.copy` already allows same space). That
is the double-buffering case: two HBM residencies of one object.

`stor.transfer` does **not** require a space change, for the same reason.

## 2. Unified events

`!sched.token` is a **generic completion event**. It is not owned by `comm`.

Any async-capable op may produce or consume a token:

```text
Storage task  ──► !sched.token
Compute task  ──► !sched.token
Comm task     ──► !sched.token
```

Producers in this phase:

| Op | Token |
| -- | ----- |
| `comm.stream` | Always |
| `comm.copy` | Optional (`-> !sched.token` means non-blocking) |
| `sched.task` | Always (region completion) |

`sched.wait` / `comm.barrier` consume tokens.

Phase 2 may lower `!sched.token` to `!async.token`. The semantic IR does **not**
embed `async.token`.

## 3. Generic concurrency

`sched.overlap { compute } { communicate }` is kept as **2-way sugar**.

The core construct is N-way:

```mlir
%y = sched.concurrent -> tensor<1x4096xf16> {
  %tc, %out = sched.task -> tensor<1x4096xf16> {
    sched.wait %t_gate, %t_up : !sched.token, !sched.token
    %out = comp.gated_mlp ...
    sched.yield %out : tensor<1x4096xf16>
  }
  %ts = sched.task {
    %t_down = comm.stream %w_down_ssd, %w_down_hbm : ... -> !sched.token
    sched.yield
  }
  sched.yield %out : tensor<1x4096xf16>
}
```

`sched.task`:

- Always produces a `!sched.token` (first result)
- Additional results match `sched.yield` operands (visible to the parent)
- Body is not isolated-from-above

Tasks may contain storage, compute, or communication. Concurrency is
`Concurrent(A, B, C)`, not `Overlap(Compute, Comm)`.

## 4. Target memory-space mapping

`#stor.space` / the `Space` enum are **logical**. Enum discriminants
(`hbm=3`, `ssd=4`) are not a hardware ABI.

`--convert-stor-to-memref` maps logical spaces to integer memref memory
spaces through a **target map**:

```text
default: register=0,sram=1,dram=2,hbm=3,ssd=4,cim=5,host=6
override: --convert-stor-to-memref="space-map=hbm=9,ssd=100"
```

Unspecified names keep the default. Different targets (CUDA, NPU, CIM) pass
different maps; S²C² IR does not change.

## 5. Composite compute contract (`gated_mlp`)

`comp.gated_mlp` stays a **fused candidate** (Option B), not a mandatory
expansion. Storage/schedule analysis may keep it fused (HBM-resident, CIM MVM)
or request expansion (tiny SRAM, SSD chunk streaming).

Decomposition (when requested):

```text
hidden = act(x @ Wg) * (x @ Wu)
y      = hidden @ Wd
```

`act` is `silu` (default), `gelu`, or `relu`.

Pass: `--expand-comp-composites`. Default pipelines do **not** run it.

## 6. Test IDs

See `docs/design/test-plan.md` (S3–S5, M3, H2–H3, V2, C2, I1 update).
