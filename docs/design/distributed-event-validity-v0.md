# Distributed Event-Validity v0

**Status:** RFC. This page is the spec for D0–D3. D0 is this page
alone: it adds no op, no pass, and no test. `can-run-plan` stays `no`.
`next_cut` stays `NOT OPENED`. Recording this page does not open a cut
and does not change the W0-3/2 apply host.

The question this page answers: when is a program a distributed
computation, as opposed to a storage-aware single-device program that
happens to mention two buffers?

```text
Global Object → Local Shard → Residency → Collective completion
             → Validity → cross-rank HB
```

That chain is **Distributed Event-Validity**. Storage, compute,
communication, and execution stay what
[`execution-semantics.md`](execution-semantics.md) already froze.
This page extends happens-before with a rank index. It does not replace
that relation.

## Binding decisions

| Decision | v0 rule |
| --- | --- |
| Carrier | Upstream MLIR `shard` (LLVM 22). Shardy may later be a frontend that emits `shard`. v0 does not parse Shardy and does not vendor a copy of `shard`. |
| Dialects that stay | `stor`, `comp`, `comm`, `sched`. The coverage dialect `dist` merged in #407 stays as it is. |
| Dialect that is not added | No `dist.mesh`, `dist.place`, `dist.allreduce`, or a parallel collective op on `comm`. PR #408 is a different change and is not part of this RFC. |
| Mesh | A mesh is the set of logical participants. It is not a physical topology, not a line or a hardware grid, and not a storage space. |
| Happens-before | Intra-rank HB is the frozen relation. Cross-rank order is `HB_D`, defined below. |
| MeshSize = 1 | The program is the existing single-device program. `HB_D` adds no edge. |
| Runtime | No NCCL, HCCL, or MPI. A collective in this IR is not a library call. |
| Evidence | A profiler trace, including an Ascend trace, is not a happens-before proof. |

LLVM 20 and 21 spell this upstream dialect `mesh`. v0 uses the LLVM 22
spelling `shard`. D1 moves the `check-s2c2` CI job to LLVM/MLIR 22 so
the tests name `shard.all_reduce` and not a local stand-in. The CMake
floor for the existing dialects stays 20. A build that cannot see
`MLIRShard` has not implemented this page.

Upstream names the participant symbol `shard.grid`. This page calls
that symbol a **mesh**. There is no op named `shard.mesh`.

## 1. Mesh

A mesh is a `shard.grid` with a static shape. Every extent is a
positive integer. A `?` extent is rejected (`F02`): ranks would not be
enumerable.

```text
MeshSize = product of the extents
rank     = row-major linear index in 0 .. MeshSize-1
```

The linear index is the one `shard.process_linear_index` documents. For
shape `2x2`, coordinate `(i, j)` has rank `j + 2*i`. v0 collectives use
the whole mesh: `grid_axes` lists every axis, in any order. A proper
subgroup is outside v0.

```mlir
shard.grid @tp(shape = 2)
```

`MeshSize = 1` (`shard.grid @m(shape = 1)`) is one participant. Local
shape equals global shape. A collective on that mesh is a local
identity: it adds no cross-rank edge. `--check-s2c2-execution` on the
same storage and schedule, ignoring the `shard` ops, is the single-device
oracle. `--check-s2c2-hb-d` must accept the program exactly when that
oracle would accept the storage and schedule part.

Two `stor.materialize` results in `hbm` are two residencies of one
logical object (the double-buffer case already in `stor.materialize`).
They are not two ranks. `#comp.unit` is a unit kind, not a coordinate.
`!stor.buffer` does not grow a device parameter.

## 2. Sharding

A sharding is one `shard.sharding` value. v0 accepts either of these
shapes and rejects the rest (`F04` when a local type disagrees, `F02`
when the grid or the axis list is illegal):

| Form | `split_axes` | Meaning |
| --- | --- | --- |
| Replicated | one empty inner list per tensor axis, or a single `[[]]` when the op is fully replicated | every rank holds the whole tensor |
| Single-axis | exactly one inner list is non-empty, and that list holds exactly one grid axis | that tensor axis is partitioned across that grid axis |

`halo_sizes` is rejected. A dynamic offset is rejected. Off the
partitioned tensor axis, the local extent equals the global extent.

**Uniform tile.** If `sharded_dims_offsets` is absent, the partitioned
extent must be divisible by the grid extent on the split axis. Rank `r`
along that axis owns the half-open interval

```text
[r * tile, (r + 1) * tile)    tile = extent / gridExtent
```

**Explicit tiles.** If `sharded_dims_offsets` is present, it is the
prefix-sum vector upstream already defines: `N + 1` entries for `N`
participants on that axis. Rank `r` owns `[offsets[r], offsets[r+1])`.

Global shape and local shape may differ. They differ only on the
partitioned axis, and only by the tile of that rank.

`shard.shard` may annotate a tensor value. It does not by itself create
a `stor` object, a residency, or an event.

The coverage decision is the one `dist.distribution` already implements,
applied to the tiles of the sharding (and, when a `dist.distribution`
of the same global tensor and the same axis is present in the function,
to those `dist.shard` ranges as well):

1. A range outside `[0, extent)` is out of bounds (`shard range exceeds the global tensor`).
2. Two ranges that intersect overlap. Touching endpoints do not (`shards overlap`).
3. Any other union that is not the whole axis does not cover (`shards do not cover the global tensor`).

Overlap is reported before a gap when both are present. A replicated
sharding has no partition axis. Full copies are not overlap and are not
a gap. This decision is still made from the IR alone. D1's
`--check-s2c2-distribution` is that procedure. It does not become
undecidable because a local shape differs from the global shape.

When the function contains both a `dist.distribution` and a
`stor.localize` chain for the same global tensor shape and the same
axis, the `dist.shard` tiles and the localize tiles are the same
multiset. A mismatch is `distribution tiles do not match local shards`.
`dist` itself grows no operand and no attribute. PR #408's placement
ops are not required and are not added.

## 3. Ownership

| Placement | Who may pack or unpack the local residency |
| --- | --- |
| Replicated | every rank of the mesh |
| Single-axis shard | only the rank whose tile is that interval |

A use by any other rank is `F05` (`rank does not own this shard`).
Ownership is not a device id and not a memory space. Rank `r` may hold
the same local object in `host` and in `hbm`; both residencies are that
rank's.

## 4. Global object, local shard, residency

`stor.materialize` keeps its rule: the buffer payload equals the
logical object it materializes. The global tensor and the local tile
are different logical objects, linked by a new op in `stor` (D1), not
by relaxing that rule.

```mlir
%sharding = shard.sharding @tp split_axes = [[0]] : !shard.sharding
%global = stor.object : !stor.object<tensor<4x8xf32>>
%local = stor.localize %global to %sharding rank = 0
    : !stor.object<tensor<4x8xf32>>, !shard.sharding
   -> !stor.object<tensor<2x8xf32>>
%hbm = stor.materialize %local
    : !stor.object<tensor<2x8xf32>> -> !stor.buffer<tensor<2x8xf32>, hbm>
```

`stor.localize` (D1):

| | |
| --- | --- |
| Operands | a `stor.object` (the global object) and a `!shard.sharding` |
| Attribute | `rank`, an `i64` |
| Result | a new `stor.object` whose payload is that rank's tile |
| Effects | pure. Not a residency. Does not establish validity. Not a collective. |

The result is the **local shard** as a logical object. `stor.materialize`
of that result is the **residency**. A second `stor.materialize` of the
same local object is another residency of the same rank (another space,
or a double buffer). It does not allocate a new rank.

`stor.transfer`, `stor.pack`, `stor.unpack`, `comm.copy`, and
`comm.stream` keep their current verifiers. A transfer between two
residencies of the same local object is an intra-rank move. It is the
existing happens-before edge, not `HB_D`.

## 5. Collective well-formedness

v0 checks three upstream collectives. Each is one SPMD op. The
participant set is every rank of its mesh. The op is the completion
event `C`. It returns a tensor. It does not write a `!stor.buffer` and
it does not produce a `!sched.token`.

| Id | Op | Input on each rank | Result on each rank |
| --- | --- | --- | --- |
| D01 | `shard.all_reduce` | the same shape (a partial) | the same shape, replicated |
| D02 | `shard.all_gather` | the local tile | the concatenation along `gather_axis` |
| D02 | `shard.reduce_scatter` | the same unreduced shape | that rank's tile along `scatter_axis` |

`grid_axes` is written out and lists every axis of the mesh. An empty
`grid_axes` is the upstream identity fold, not a collective (`F05`,
`empty grid_axes is not a collective`).

`reduction` on D01 and on reduce-scatter is `sum` unless the op names
another upstream reduction kind. The kind does not change the event.

A collective is well-formed when all of the following hold. The first
failure is the diagnostic in the `F` table.

1. The `on @grid` symbol is a v0 mesh.
2. Every rank `0 .. MeshSize-1` has a `stor.localize` of one global object at that sharding, a residency of that local object, a `stor.pack` of the input tensor into that residency, and a later `stor.pack` of the collective's result tensor into a result residency that this rank owns.
3. The input tensor of the collective is a `stor.unpack` of that rank's input residency, and the unpack is HB-before `C` inside the rank.
4. Input and result types match the row in the table above.
5. `comm.copy` and `comm.stream` are not this event, whatever `#comm.kind` they carry.

D01 is tensor-parallel all-reduce: each rank's partial has the result
shape (replicated sharding, `split_axes = [[]]`), and `C` makes the
reduced tensor available on every rank. A following `comp.matmul` that
unpacks the result residency is ordered after `C`.

D02 is one all-gather and one reduce-scatter, each meeting the table.
Local shape and global shape differ on the gathered or scattered axis.

**D03, AllToAllV, is v0.1.** Variable per-rank split sizes are not a v0
collective. LLVM 22's `shard.all_to_all` is the equal-split collective,
which is a different op and is also outside the three rows above. v0
rejects `shard.all_to_all` with `all-to-all is v0.1`. It is not rewritten
into all-gather and it is not given an `HB_D` rule.

`shard.send`, `shard.recv`, `shard.reduce`, `shard.broadcast`,
`shard.gather`, `shard.scatter`, `shard.shift`, and `shard.update_halo`
are outside v0 and produce `collective is outside distributed semantics v0`.

## 6. Validity

Validity stays a predicate on a residency, not a field of the event.

| Event | What becomes valid |
| --- | --- |
| `stor.pack`, `stor.transfer`, `comm.copy`, `comm.stream` | the destination residency, by the frozen rule |
| Collective completion `C` | no residency, until a rank packs `C`'s result tensor |

`C` makes the result *tensor* available. The result *residency* becomes
valid only at the pack of that tensor. An unpack of a buffer whose
establishing write is not a pack of `C`'s result is `F06`
(`collective result is not valid`), including the case where the buffer
was packed with the pre-collective partial and is therefore a defined
read of the partial for `--check-s2c2-execution`.

## 7. HB_D

Frozen happens-before, written `→HB`, is the irreflexive transitive
closure of program order and synchronizes-with
([`execution-semantics.md`](execution-semantics.md) §3). Sibling order
inside `sched.concurrent` is still not an edge.

`HB_D` is that relation indexed by rank, plus the collective edges.

```text
For each rank r:
  →HB_D restricted to actions of r   =   →HB of those actions

For a well-formed collective C on mesh M, for all ranks r, q in M:
  input-pack(C, r)  →HB_D  C  →HB_D  result-pack(C, q)
  C                 →HB_D  result-unpack(C, q)
```

Actions of rank `r` are the `stor.localize` of rank `r` and every
`stor` / `comm` / `comp` / `sched` op that uses the local object, the
residencies, or the tensors unpacked from them. A collective is an
action of every rank in its mesh. An op that only uses a global object
with no localize is a single-device action: it has a rank only when
`MeshSize = 1`.

`input-pack(C, r) →HB_D result-unpack(C, q)` for `r ≠ q` is the
cross-rank edge. It is not implied by the two ops sitting in one
function, and it is not implied by SSA across two concurrent tasks.
Textual order of those tasks does not create it. The edge exists when
the input pack reaches `C` in rank `r`'s `→HB` and `C` reaches the
result unpack in rank `q`'s `→HB`, or when a `sched.wait` /
`comm.barrier` on an event that witnesses `C` does.

`MeshSize = 1` adds none of the cross-rank edges. The one rank's
`→HB_D` is `→HB`.

`--check-s2c2-hb-d` (D2) builds this relation. It does not lower
tokens and it does not call a runtime. On a program with no `shard.grid`
and no collective it agrees with `--check-s2c2-execution`.

## 8. Faults F01–F08

Each fault is one `expected-error` from `--check-s2c2-hb-d`. The
diagnostic text is the sentence in the table, so a test can match it.
F03 reuses the three coverage sentences from §2; the test's function
name is still `@f03`.

| Id | Sentence the checker emits | The broken link |
| --- | --- | --- |
| F01 | `HBM residencies are not mesh participants` | Two `hbm` materializations are used as the participant set (a collective, or a rank attribute on those buffers) while they are residencies. |
| F02 | `rank is outside the mesh` | `rank` is negative or `≥ MeshSize`, the grid symbol is missing, an extent is `?`, or `grid_axes` is not the full mesh. |
| F03 | the §2 coverage sentence | Single-axis tiles are out of bounds, overlap, or leave a gap, in that order. |
| F04 | `local shape is not the shard tile` | The `stor.localize` result payload is not the tile of that rank. Global and local are allowed to differ only by that tile. |
| F05 | `rank does not own this shard` or `pairwise copy is not a collective` or `empty grid_axes is not a collective` | Ownership fails, or `comm.copy` / `comm.stream` is the stand-in for `C`, or `grid_axes` is empty. |
| F06 | `collective result is not valid` | A read observes a residency whose establishing write is not a pack of `C`'s result tensor. |
| F07 | `collective drops a participant` | Some rank of the mesh has no localize, no input pack, or no result pack for `C`. |
| F08 | `missing cross-rank happens-before` | A result unpack on rank `q` is not `HB_D`-after `C`, or an input pack on rank `r` is not `HB_D`-before `C`. Concurrent sibling order does not supply the edge. |

F07 and F08 are also the lowering faults in §9. A source program that
already drops a rank or an edge is rejected here. A lowering that
introduces that shape is rejected by the fidelity check.

## 9. Lowering fidelity

D3 lowers nothing to a device library. `shard.all_reduce`,
`shard.all_gather`, and `shard.reduce_scatter` stay those ops.
Participants stay the `rank` attributes of `stor.localize`.

Two realizations:

**Async.** `--lower-s2c2-hb-d=async` wraps `C` in a `sched.task` when it
is not already inside one, yields `C`'s result tensor, and places each
rank's result pack and later reads after a `sched.wait` of that task
event when program order does not already order them. Existing
token-to-async may then run. The source relation is kept:

```text
HB_source  ⊆  HB_target
```

on the images of the source actions. The image of a localize is the
localize with the same `rank`. The image of `C` is the same collective
op, whether or not it now sits in a task. An edge `a →HB_D b` in the
source must still hold between those images. The target may contain
extra edges. It may not drop a rank (`F07`) and it may not drop a source
edge (`F08`).

**Sync.** `--lower-s2c2-hb-d=sync` emits one block that is a linear
extension of `HB_D`: if `a →HB_D b`, then `a` is textually before `b`.
Extra order among actions that were unordered is allowed. That extra
order is the same kind of legal total order Phase 2A already allows for
`→HB`. It is not a new semantic edge the source was missing. The block
still contains every rank's localize and the collective. Dropping a rank
is `F07`. Deleting a required order is `F08`.

`--check-s2c2-hb-d-fidelity` takes `mode=async` or `mode=sync`, compares
the relation before and after the matching lower pass, and emits `F07`
or `F08` when the inclusion fails. MeshSize = 1 lowers as today's
single-device schedule: the async path is the existing token path, and
the sync path is a linear extension of `→HB`.

## 10. Tests each later phase must name

D1, `--check-s2c2-distribution` (no HB yet):

| Test | What a pass proves |
| --- | --- |
| `test/Distribution/replicas-are-not-devices.mlir` `@two_hbm_materialize_are_not_devices` | Prints `hbm-replicas=2 mesh-size=2 residencies-are-devices=no`. A grid is in the module. The two `hbm` buffers are not its ranks. |
| `test/Distribution/coverage.mlir` `@single_axis_cover` | Prints `coverage=axis0:covered distribution-stor=match`. Global `tensor<4x8xf32>`, local `tensor<2x8xf32>`, tiles agree with a `dist.distribution` on axis 0. |
| `test/Distribution/coverage.mlir` `@single_axis_gap` | `expected-error` `shards do not cover the global tensor`. |
| `test/Distribution/mesh-size-one.mlir` `@mesh_size_one_local_matches_global` | MeshSize 1, local shape equals global shape, prints `coverage=replicated:covered mesh-size=1`. |

Existing `test/Dist/cover.mlir` and `test/Dist/invalid.mlir` stay green
and stay on `dist` alone.

D2, `--check-s2c2-hb-d`:

| Test | Result |
| --- | --- |
| `test/Distribution/hb-d-invalid.mlir` `@f01` … `@f08` | `expected-error`, one fault each, text from §8 |
| `test/Distribution/hb-d.mlir` `@d01_tensor_parallel_all_reduce` | pass |
| `test/Distribution/hb-d.mlir` `@d02_all_gather` | pass |
| `test/Distribution/hb-d.mlir` `@d02_reduce_scatter` | pass |
| `test/Distribution/hb-d.mlir` `@d05_multilevel_storage` | pass. One rank, residencies in `host` and `hbm`, intra-rank `comm.stream` or `stor.transfer`, then the collective on the `hbm` residency. The two spaces are not two participants. |
| `test/Distribution/hb-d.mlir` `@mesh_size_one` | pass, and `--check-s2c2-execution` passes on the same file |
| `test/Distribution/all-to-all-v.mlir` `@d03_all_to_all_v` | `expected-error` `all-to-all is v0.1` |

D3, lower then `--check-s2c2-hb-d-fidelity`:

| Test | What a pass proves |
| --- | --- |
| `test/Distribution/hb-d-lower.mlir` `@d01_async_keeps_edges` | After `mode=async`, both ranks and `shard.all_reduce` are still in the IR, and every source `HB_D` edge is still present. |
| `test/Distribution/hb-d-lower.mlir` `@d01_sync_is_linear_extension` | After `mode=sync`, the block is a linear extension: source edges point forward, and both ranks remain. |
| `test/Distribution/hb-d-lower-invalid.mlir` `@f07_dropped_rank` `@f08_deleted_edge` | The fidelity checker emits `F07` and `F08` on a lowered shape that dropped a participant or a required edge. |

## 11. What stays put

`can-run-plan` stays `no`. `next_cut` stays `NOT OPENED`. The W0-3/2
apply host is unchanged. `execution-semantics.md` is unchanged; §7 cites
it and does not edit it. No test treats an Ascend, CUDA, or other
profiler trace as a happens-before witness.
