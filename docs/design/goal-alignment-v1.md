# Goal Alignment v1

**Status:** documentation checkpoint. Not a new semantic
baseline. Semantic baseline remains
`36fd6fd931c109c6849cc366bd91b5abdfcab4b1`.
This page does not change a dialect, the IR, or Apply.
`next_cut` stays `NOT OPENED`.

```text
Goal     keep the research direction and the current delivery apart
Not      a Token Path contract, a cluster contract, or a new op
Rewrite  still closed; can-run-plan stays no
```

Product lock: [`compiler-spine.md`](compiler-spine.md).
Evidence lock: [`empirical-semantic-boundary-v1.md`](empirical-semantic-boundary-v1.md).
Carrier: [`mlir-carrier-v0.md`](mlir-carrier-v0.md).

```bash
python3 runtime/record_goal_alignment.py --print-goal-alignment
```

The command passes only when the op list below matches
`include/s2c2`. It does not apply IR.

The industry report (异构编译与集群编译, Rubin mathematical
modeling edition) and this repository share one direction.
They do not share one delivery target.

## Shared direction

Both state the same research question.

```text
When a token path crosses storage, compute, communication,
and execution, the IR has to name that composition.
```

The composition is `stor` / `comp` / `comm` / `sched`.
`sched` is the happens-before layer. A vendor stack is a
realization of that composition. It is not the definition
of the IR. Legality, sufficiency, and authorization stay
separate facts. Absence of an ordering requirement is not
a claim that the hardware runs the tasks together.

That direction is the report's thesis and this tree's
question. It is not a license to add the report's pictures
as ops.

## Current delivery

This cut is finished when these five statements stay true.

```text
1. The dialect ops are the ones in include/s2c2, listed below.
2. The apply host is W0-3/2 only.
3. can-run-plan stays no.
4. The carrier text and s2c2-opt stay separate.
5. next_cut stays NOT OPENED.
```

### Ops that exist

```text
stor     object, materialize, transfer, alloc, dealloc, pack, unpack
         spaces: register, sram, dram, hbm, ssd, cim, host
comp     matmul, elemwise, gated_mlp
         optional unit: cpu, gpu, npu, cim
comm     copy, stream, barrier
         kind: p2p, broadcast, reduce
         engine: dma, copy, noc
sched    yield, wait, task, concurrent, overlap, pipeline, stage
         !sched.token
```

`comp.gated_mlp` is the fused gated MLP. It is not an
expert operator. `sched.pipeline` and `sched.wait` are
real. There is no `sched.hb` op. Happens-before is the
relation those schedule ops carry.

### Host

W0-3/2 is one device, one contiguous region, capacity 2.
It stores K1, K2, and E. The machinery steps are
KEEP, EVICT, TRANSFER, RESTORE. `evaluate_apply` matches
a plan, builds a candidate without editing the source,
checks a happens-before projection and an external
witness, then commits or discards. A successful apply is
still not permission to run a plan.

### Carrier

`runtime/record_mlir_carrier.py` projects carrier text
onto the host program `evaluate_apply` already reads.
`s2c2-opt` does not register that text. The host does not
parse MLIR. MLIR `stor.transfer` is a residency copy. The
host string `"transfer"` is a candidate-construction step.

### What stays closed

```text
distributed semantic v2
routing dialect
collective / all-to-all op
new HB rule
Enum_F / Search
generic rewrite
Token Path inhabitant
cluster topology as a compiler object
```

The eighteen Ascend 910B2 runs in the evidence lock are
`OUTSIDE-CONTRACT`. `semantic_gap` is false. Those runs
did not call Apply. A scene outside W0-3/2 is a scope
boundary. It is not, by itself, a reason to open a cut.

## Report pictures that are not this cut

The report may keep these as research sketches. This
repository does not treat them as implemented IR, and
this page does not promote them into a contract.

| Report sketch | In this tree |
| ------------- | ------------ |
| `comm.dispatch`, `comm.prefetch` | No such op. No all-to-all. |
| `comp.attention`, `comp.attn_tile` | No attention op. |
| `comp.cim_mvm`, `comp.accum`, `comp.quant` | No CIM compute op. `cim` is a storage space and an optional compute unit. |
| `sched.hb` | No such op. |
| UB, L1, GM, CMX, SMEM as IR residencies | Hardware names. Not storage spaces. |
| Program × Device × Topology × Realization | Open question in the report. Not a compiler object here. |
| DeepSeek-V4 / Kimi K3 decode path | Workload archetype in the report. Not an inhabitant. |
| CUDA / CANN / ROCm / CIM as native backends | Vendor realization. `s2c2-opt` is not those backends. |

`s2c2-translate` is a translation driver stub.
`s2c2-cuda-adapter` is a host dry-run. Neither applies
the W0-3/2 host.

## One slide, if the report needs a status page

Insert [`goal-alignment-v1-status.pptx`](goal-alignment-v1-status.pptx)
after the report's architecture picture. It is a status
page for this tree. It does not replace the report and
it does not add an op.

```text
S²C²IR status on this tree

Direction
  Storage × Compute × Communication × Execution
  one composition semantics, many realizations

This cut
  ops: stor / comp.matmul|elemwise|gated_mlp / comm.copy|stream|barrier
       sched.task|concurrent|overlap|pipeline|stage|wait
  host: one device, one region, capacity 2
        KEEP → EVICT → TRANSFER → RESTORE
  can-run-plan = no
  carrier text ≠ s2c2-opt
  semantic baseline = 36fd6fd
  next_cut = NOT OPENED

Not this cut
  Token Path, MoE dispatch, cluster topology, CIM MVM
  those stay research sketches until a cut is opened
```
