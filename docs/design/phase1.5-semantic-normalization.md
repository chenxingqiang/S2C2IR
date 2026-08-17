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

| Op | Meaning | Contents |
| -- | ------- | -------- |
| `stor.object` | Create a logical identity (no allocation) | n/a |
| `stor.materialize` | Allocate a residency of an object in the result space | **unspecified** |
| `stor.transfer` | Allocate a new residency and copy payload (same object) | dest **valid** |
| `stor.alloc` | Anonymous residency (no object). Legacy / local scratch | unspecified |
| `stor.dealloc` | Free a residency, not the logical object | n/a |
| `stor.pack` / `stor.unpack` | Tensor ↔ residency edge | pack ⇒ dest **valid** |

### Data validity (not a state machine)

Object identity and data validity are separate. Phase 1.5 does **not**
introduce `valid/stale/dirty/inflight` attributes.

```text
materialize  ⇒  residency exists, content unspecified
transfer / copy / stream / pack  ⇒  destination becomes valid
```

```mlir
%w = stor.object ...
%w_ssd = stor.materialize %w   // allocated, uninitialized
%w_hbm = stor.materialize %w   // allocated, uninitialized
%t = comm.stream %w_ssd, %w_hbm
sched.wait %t                  // now %w_hbm is valid
```

A `!sched.token` from `comm.stream` / optional `comm.copy` means
**transfer completion: destination is valid**. Using a materialized
buffer in compute before any fill/copy is undefined.

This is the contract Phase 2B async overlap must preserve. See
[Phase 2A sequential lowering](phase2a-sequential-lowering.md).

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

`sched.wait` / `comm.barrier` consume tokens. A token from `comm.stream`
or optional `comm.copy` means the destination residency is **valid**. A
token from `sched.task` means the region completed.

Phase 2 may lower `!sched.token` to `!async.token`. The semantic IR does **not**
embed `async.token`. Sequentialize in Phase 2A erases these events as a
blocking baseline; that is not the semantic definition.

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

`sched.concurrent` means **no ordering requirement** among children, not
“must execute in parallel”:

```text
NoOrderingRequirement(A, B, C)
SequentialSchedule ∈ ValidSchedules
```

Sequentialization may pick any legal total order consistent with
explicit token / `sched.wait` dependencies. Phase 2A / v0.1: the
concurrent body may contain only direct `sched.task` children (plus
`sched.yield`). Nested structured schedule is rejected until Phase 2B.

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

`comp.matmul` means `C = A @ B`. `comp.elemwise` is **canonical math**,
not a fixed instruction sequence. Phase 2A linalg lowering is one
realization (see [phase2a-sequential-lowering.md](phase2a-sequential-lowering.md)).

## 6. Test IDs

See `docs/design/test-plan.md` (S3–S5, M3, H2–H4, V2, C2, I1 update).
