# Phase 2B: v0.1 pipeline lowering (chained await)

Status: **implementation**. Realizes frozen v0.1 `StageOrder`. Does not
redefine Execution Semantics and does not add iteration IR.

Acceptance:

```text
StageOrder_source  ⊆  HB_lowered
```

not “the pipeline runs in parallel.”

Prerequisite: [`pipeline-semantics.md`](pipeline-semantics.md) (frozen
v0.1). Token / concurrent slices stay unchanged.

Out of scope:

- iteration / trip count / software pipelining
- relaxing `InstanceOrder` / SoftPipe
- `sched.overlap` lowering
- unordered `N × async.execute` (that is concurrent, not pipeline)

## 1. Rewrite

v0.1 pipeline is one implicit instance:

```text
S1  →HB  S2  →HB  …  →HB  Sk
completion(P) = yield(Sk)
```

The parent action after `P` is HB-after every stage.

Conservative realization (parent-level chained await):

```text
%t1 = async.execute { S1 }
async.await %t1
%t2 = async.execute { S2 }
async.await %t2
…
%tk = async.execute { Sk }
async.await %tk
```

Each successor is launched only after the predecessor token is awaited.
That is `yield(S_i) →HB entry(S_{i+1})`. Joining `Sk` is pipeline
completion (unlike concurrent, unused sibling tokens are not left
unjoined).

Forbidden:

```text
async.execute S1
async.execute S2
async.execute S3
// no await
```

Stage bodies are cloned with the same operand / leftover-execute remap
as waited tasks (nested transfer execute + await at stage completion
when the transfer is not flattened). `StageOrder` is the extra
invariant; it is not A4 flatten and not concurrent explode.

## 2. Tests

| ID | Must show |
| -- | --------- |
| P1 | E6 shape: await of S1 (pack) before S2 unpack |
| P2 | three stages: await between each pair of executes |
| P3 | stage-local SSA remapped inside that stage’s execute |

E6 / E8 remain on `--check-s2c2-execution` (semantic IR).
