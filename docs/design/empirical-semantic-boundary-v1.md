# Empirical Semantic Boundary v1

**Status:** documentation checkpoint. Not a new semantic
baseline. Semantic baseline remains
`36fd6fd931c109c6849cc366bd91b5abdfcab4b1`.
This page does not change a dialect, the IR, or Apply.
Evidence Review of the corpus below is PASS.
Real hardware collection is stopped.

```text
Goal     freeze what the tested runs do and do not claim
Not      a distributed semantic v2, a new HB rule, or a cut
Rewrite  still closed; Apply was not called by these runs
```

Product lock: [`compiler-spine.md`](compiler-spine.md).

## Three layers

Every row below is read in this order. A fact on an upper
layer does not become a claim on a lower layer.

```text
REAL EXECUTION
    ↓
OBSERVED BEHAVIOR
    ↓
S²C²IR SEMANTIC CLAIM
```

| Layer | May record | May not record |
| ----- | ---------- | -------------- |
| Real execution | The process ran. Values, kernel names, streams, and event or task counts came from that run. | That the W0-3/2 inhabitant expresses the scene. |
| Observed behavior | The API that was called, the device kernel that ran, the host tensor that was read back, and `ordering_grade`. | A compiler-visible happens-before edge. `semantic_gap=true`. |
| S²C²IR semantic claim | The run is outside the current inhabitant, or it is not. Inside this tested range, no expressiveness failure was found. | That S²C²IR expresses every real distributed execution semantics. |

Frozen sentence:

> 在当前实际测试覆盖的 workload 和观察范围内，未发现足以构成 `semantic_gap=true` 的表达失败。

Inside the workloads and observations actually tested, no
expressiveness failure sufficient for `semantic_gap=true`
was found.

Three distinctions stay in force:

```text
OUTSIDE-CONTRACT  ≠  SEMANTIC GAP
runtime observation  ≠  HB
API intent  ≠  device realization
```

`semantic_gap` becomes true only when `stor`, `comp`,
`comm`, and `sched`, taken together, are shown unable to
express a necessary relation. A scene the W0-3/2
inhabitant does not carry is not that demonstration.
A profiler `EVENT_RECORD`, `EVENT_WAIT`, or `Notify Wait`
is runtime bookkeeping. Kernel order is not an HB proof.
`hb_proof` stays false unless a compiler-visible HB edge
was produced by the frozen inhabitant. The device kernel
in the trace is the realization. The API name is not.

## Why the semantics stay frozen

```text
W0-3/2 inhabitant
    = one restricted realization inhabitant
    ≠ the distributed / collective semantic model
```

The inhabitant names one device and one contiguous region.
It stores exactly K1, K2, and E, with capacity 2, and it
realizes KEEP, EVICT, TRANSFER, and RESTORE.
`can-run-plan` stays no. That inhabitant is not a model of
expert routing, tensor parallel, pipeline send, or a
collective.

The runs below fall outside that inhabitant. Each one
shows an inhabitant scope boundary. None of them shows
that the four dimensions cannot name the relation that
ran.

NEXT CUT opens only when all of the following hold:

```text
real scene
    → stor / comp / comm / sched, composed,
      still cannot express a necessary relation
    → not an illegal input, a missing witness,
      or a plan mismatch
    → then propose a new contract
```

These are not reasons to open a cut:

```text
another collective
OUTSIDE-CONTRACT by itself
a richer inhabitant
W0-3/2 → W0-3/4
a routing dialect
a new HB rule
Enum_F
Search
generic rewrite
a performance measurement
```

## Corpus

Eighteen closed runs. Seventeen use two Ascend 910B2
devices. W2-910B2-001 is the local MoE step on one device
and is one of the eighteen. Classification is
OUTSIDE-CONTRACT. `semantic_gap` is false. `hb_proof` is
false. `new_contract` is NONE. `next_cut` is NOT OPENED.
Apply was not called. The repository was not modified by
the runs.

| id | form | device kernel that ran | ordering_grade |
| --- | --- | --- | --- |
| W2-910B2-001 | single-device top-2 MoE | MoeGatingTopKSoftmax, GroupedMatmul, MoeFinalizeRoutingV2 | observed-order-only |
| W2-910B2-002 | dual-device top-1 alltoallv | hcom_alltoallv, aclnnMatmul | runtime-events-present |
| W2-910B2-003 | top-1, owner scale, return alltoallv | hcom_alltoallv, aclnnMuls | runtime-events-present |
| W2-910B2-004 | top-2, owner scale, return alltoallv | hcom_alltoallv, aclnnMuls | runtime-events-present |
| W3-910B2-001 | alltoall, then matmul, host sync between them | hcom_alltoall, aclnnMatmul | runtime-events-present |
| W3-910B2-002 | three arms, no host sync between collective and matmul | hcom_alltoall, aclnnMatmul | observed-order-only |
| TP-910B2-001 | column-parallel matmul, all_gather | hcom_allGather, aclnnMatmul | runtime-events-present |
| TP-910B2-002 | row-parallel matmul, all_reduce | hcom_allReduce, aclnnMatmul | runtime-events-present |
| PP-910B2-001 | one-direction send, then second matmul | hcom_send, hcom_receive, aclnnMatmul | runtime-events-present |
| RS-910B2-001 | matmul, reduce_scatter | hcom_reduceScatter | runtime-events-present |
| BC-910B2-001 | weight broadcast, then matmul | hcom_broadcast, aclnnMatmul | runtime-events-present |
| GV-910B2-001 | `dist.gather` | hcom_broadcast, hcom_allGather | runtime-events-present |
| SC-910B2-001 | `dist.scatter`, then matmul | hcom_scatter, aclnnMatmul | runtime-events-present |
| AR-910B2-001 | `dist.all_reduce` SUM | hcom_allReduce | runtime-events-present |
| RED-910B2-001 | `dist.reduce` to rank 0 | hcom_reduce | runtime-events-present |
| P2P-910B2-001 | send/recv both directions, then mul | hcom_send, hcom_receive, aclnnMuls | runtime-events-present |
| A2A-910B2-001 | equal-split `all_to_all_single` | hcom_alltoallv | runtime-events-present |
| BAR-910B2-001 | mul, `dist.barrier`, mul | hcom_allReduce between two muls | runtime-events-present |

`ordering_grade = runtime-events-present` means the trace
contains event, stream wait, notify, or completion
records. Those records are not an S²C²IR HB edge.
W2-910B2-001 has no such records. W3-910B2-002 stays
`observed-order-only` because the no-wait arm has no
`EVENT_WAIT` on the matmul stream. HCCL still emits events
on the collective streams of that run. A later kernel
timestamp is not a completion edge.

The kernel column names the kernels that distinguish the
form. W2-910B2-002, W2-910B2-003, and W2-910B2-004 also
contain `MoeGatingTopKSoftmax` and `hcom_allGather` before
`hcom_alltoallv`. TP-910B2-001 also contains `PadV3` and
`aclnnCat`. W2-910B2-001's GroupedMatmul is
`aclnnGroupedMatmulV5`.

API calls whose device kernel was a different HCCL op:

- `dist.gather` ran as broadcast plus `hcom_allGather`. There is no `hcom_gather`. A root-only gather is not established.
- `dist.all_to_all_single` with equal splits ran as `hcom_alltoallv`. There is no separate alltoall kernel. This is the same kernel family as the W2 variable-size exchanges. W3's `hcom_alltoall` remains a different kernel name.
- `dist.barrier` ran as `hcom_allReduce`. There is no payload-free barrier kernel.
- `dist.reduce` ran as `hcom_reduce` on both ranks, which is not `hcom_allReduce`. Rank 0 read back the sum. Rank 1's host tensor still read back as its input. That host readback does not show that the non-root device buffer was unused inside HCCL.

Two earlier NVIDIA observations are outside this table.
W2-moe-001 is one RTX 5090 fused MoE, OUTSIDE-CONTRACT,
`semantic_gap` false, with no second device. W3-gpu0-gpu1-001
is a two-GPU NCCL exchange, OUTSIDE-CONTRACT, `semantic_gap`
false. A later nsys report from a container with no GPU
device nodes is not evidence.

## What this checkpoint does not do

```text
baseline            stays 36fd6fd until a separate approval
dialect             unchanged
IR                  unchanged
Apply               unchanged
can-run-plan        stays no
Enum_F              stays closed
Search              stays closed
generic rewrite     stays closed
extract             unimplemented
new contract        NONE
NEXT CUT            NOT OPENED
```

This page does not choose the next engineering mainline.
After this checkpoint is reviewed, the open choice is a
carrier for the existing contract, or compiler lowering of
that same frozen contract. Neither choice is a new
contract. Neither choice is opened by this page.
