# Real Workload Expressibility Audit v1

**Status:** research record. Not a semantic baseline.
Semantic baseline remains
`36fd6fd931c109c6849cc366bd91b5abdfcab4b1`.
This page adds no dialect op, no contract, and no host
behavior. `next_cut` stays `NOT OPENED`.
`can-run-plan` stays `no`.

```text
Goal     decide whether this one real scene needs a new cut
Not      a Token Path, a backend, a cluster contract, or 7C
Rewrite  still closed; this page does not apply IR
```

Product lock: [`compiler-spine.md`](compiler-spine.md).
Evidence lock: [`empirical-semantic-boundary-v1.md`](empirical-semantic-boundary-v1.md).

## Decision

```text
P2  the four dialects express the necessary relations
    this scene actually established
    → do not open a cut
    → end this round
```

No expressibility gap was found. The misses are an
inhabitant boundary and missing witnesses. Neither is a
reason to add an op.

## Scene

One workload, already run, not designed for a new dialect.

```text
IR     test/Integration/storage-aware-pipeline.mlir
       func @ssd_pipeline_two_tiles
4090   docs/design/v3-dataset/storage-measured-4090.log
910B   docs/design/v3-dataset/storage-measured-910b.log
```

Both logs record `measured=yes`, `correctness=1`,
`program-measurement=yes`, and `semantics=unchanged`.
Timing is host wall clock. Logical SSD is a pageable host
buffer, not a disk. The 4090 transfer record is
`storage_to_host|host_to_device`. The 910B transfer record
is `host_to_device|device_to_host`. Compute is recorded as
`elemwise`. The note `workload-semantic-ne-kernel-backend`
stays in force. Wall-clock numbers are not copied here.

The eighteen Ascend collective runs stay classified in the
evidence lock. This audit does not reopen them.

## What the run establishes

```text
REAL EXECUTION
  a process ran on rtx4090 and on ascend 910B
  correctness = 1
OBSERVED BEHAVIOR
  host wall clock
  transfer names and compute=elemwise
  logical SSD ≠ disk
S²C²IR SEMANTIC CLAIM
  not an HB edge
  not a proof that the hardware overlapped the tasks
  not a proof that a gated MLP kernel ran
```

`hb_proof` is false. A later timestamp is not a
happens-before edge.

## Mapping

| Question | Result |
| -------- | ------ |
| Storage identity, residency, validity | Expressed. `stor.object` is identity. `stor.materialize` creates an `ssd` residency whose contents are unspecified. `stor.pack` is what makes those contents the tile. `stor.transfer` moves residency `ssd → host → hbm`. |
| Compute | Expressed. The IR names `comp.gated_mlp` and `comp.elemwise`. The log's `compute=elemwise` does not witness the gated MLP. That is a missing kernel witness, not a missing op. |
| Movement | Expressed as residency copy (`stor.transfer`). This function does not need `comm.stream`. A DMA-engine copy remains `comm.stream`, as in `@gated_mlp_ssd_stream`. The log does not name an engine. |
| Happens-before | Expressed. Tile 0's prologue is sequential SSA. `sched.concurrent` between the gated MLP and tile 1's prefetch means there is no ordering requirement. Tile 1's host-to-hbm transfer uses the buffer that concurrent yields, so it is after that task by SSA. No `sched.hb` op is required. |
| Capability and witness | The missing piece is a witness. Wall clock, a host buffer named SSD, and `compute=elemwise` do not become a compiler HB edge or a disk residency. |
| Legal versus illegal change | The existing execution check is the oracle for the order the IR states. A measured arm outside `F` stays outside `F` (`par-not-in-F`). Measurement does not license a rewrite. |

`sched.concurrent` and the log agree on one limit: neither
says the hardware ran the two tasks at the same time.

## Three kinds of miss

```text
expressibility gap     none for the relations this scene established
integration gap        this function is not the W0-3/2 host
                       carrier text does not carry it
                       s2c2-opt does not call evaluate_apply
evidence gap           no disk residency, no gated-MLP kernel
                       witness, no compiler-visible HB edge
implementation defect  not found by this reading
```

OUTSIDE-CONTRACT is the integration gap. It is not
`semantic_gap=true`. Repairing the handoff would still not
be a new dialect. It is also not authorized by this page:
carrier stays unregistered, and `can-run-plan` stays `no`.

## What would have opened a cut

A cut would require a necessary relation this IR cannot
state, for example a required order that is neither SSA,
nor `sched.wait` on a token, nor the absence of an order.
No such relation is established by these logs.

## P2

```text
four dialects express the necessary relations  →  stop
7C                                             →  NOT OPENED
7D / 7E / 7F                                   →  NOT OPENED
S05                                            →  known difference, unchanged
full corpus equivalence                        →  NOT CLAIMED
can-run-plan                                   →  no
Token Path / backends / cluster                →  research direction
```
